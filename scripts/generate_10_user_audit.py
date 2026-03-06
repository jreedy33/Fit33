#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════════════════════════
10 USER AUTO-GEN AUDIT - REAL DATA ONLY
═══════════════════════════════════════════════════════════════════════════════

This script generates workouts for 10 diverse user profiles using the EXACT
same logic as the iOS app. NO FAKE DATA - uses real Supabase exercise database
and real selection algorithms.

Output: Clean PDF with user profiles and generated workouts.
"""

import os
import load_env  # noqa: F401 — auto-loads .env credentials
import sys
from datetime import datetime
from typing import List, Dict, Optional, Set
from dataclasses import dataclass
from enum import Enum
import random

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Supabase connection
from supabase import create_client

# PDF Generation
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.enums import TA_CENTER, TA_LEFT

# Import combo rules (same as iOS app uses)
try:
    from workout_combo_rules import (
        detect_workout_combo,
        get_combo_rule,
        get_balance_slot,
        detect_exercise_pattern,
        validate_workout_against_rules,
        COMBO_RULES,
    )
    COMBO_RULES_AVAILABLE = True
except ImportError:
    COMBO_RULES_AVAILABLE = False
    print("⚠️ workout_combo_rules.py not found - using basic rules")

# ═══════════════════════════════════════════════════════════════════════════════
# SUPABASE - REAL DATABASE CONNECTION
# ═══════════════════════════════════════════════════════════════════════════════

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ehooeghabzefgoqzugrc.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_ANON_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ═══════════════════════════════════════════════════════════════════════════════
# DATA CLASSES
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class Limitation:
    area: str
    severity: str  # "skip_completely", "light_only", "be_careful"
    
@dataclass
class UserProfile:
    id: int
    name: str
    age: int
    gender: str
    weight_lbs: float
    experience_level: str  # "Beginner", "Intermediate", "Advanced"
    fitness_goal: str
    available_equipment: List[str]
    limitations: List[Limitation]
    workouts_completed: int
    preferred_duration_minutes: int
    
    # Auto-gen inputs
    selected_muscle_groups: List[str]  # What user selects in app
    focus_areas: List[str]  # Sub-selections like "Lats", "Upper Back", "Biceps"

# ═══════════════════════════════════════════════════════════════════════════════
# 10 DIVERSE USER PROFILES
# ═══════════════════════════════════════════════════════════════════════════════

def create_10_user_profiles() -> List[UserProfile]:
    """Create 10 diverse user profiles representing real app users"""
    
    profiles = [
        # USER 1: Complete Beginner - First Week
        UserProfile(
            id=1,
            name="Sarah Mitchell",
            age=28,
            gender="Female",
            weight_lbs=145,
            experience_level="Beginner",
            fitness_goal="Build Muscle",
            available_equipment=["Machines", "Cables", "Dumbbells"],
            limitations=[],
            workouts_completed=2,
            preferred_duration_minutes=40,
            selected_muscle_groups=["Back", "Arms"],
            focus_areas=["Lats", "Biceps"]
        ),
        
        # USER 2: Intermediate Male - Back & Biceps Focus
        UserProfile(
            id=2,
            name="Marcus Johnson",
            age=32,
            gender="Male",
            weight_lbs=185,
            experience_level="Intermediate",
            fitness_goal="Build Muscle",
            available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
            limitations=[],
            workouts_completed=45,
            preferred_duration_minutes=50,
            selected_muscle_groups=["Back", "Arms"],
            focus_areas=["Lats", "Upper Back", "Biceps"]
        ),
        
        # USER 3: Advanced with Lower Back Issue
        UserProfile(
            id=3,
            name="David Chen",
            age=38,
            gender="Male",
            weight_lbs=195,
            experience_level="Advanced",
            fitness_goal="Get Stronger",
            available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
            limitations=[Limitation("Lower Back", "be_careful")],
            workouts_completed=150,
            preferred_duration_minutes=60,
            selected_muscle_groups=["Back", "Arms"],
            focus_areas=["Lats", "Upper Back", "Biceps"]
        ),
        
        # USER 4: Female Beginner - Chest & Shoulders
        UserProfile(
            id=4,
            name="Emily Rodriguez",
            age=24,
            gender="Female",
            weight_lbs=130,
            experience_level="Beginner",
            fitness_goal="Stay Active",
            available_equipment=["Machines", "Cables", "Dumbbells"],
            limitations=[],
            workouts_completed=8,
            preferred_duration_minutes=35,
            selected_muscle_groups=["Chest", "Shoulders"],
            focus_areas=["Upper Chest", "Front Delts", "Side Delts"]
        ),
        
        # USER 5: Older Male - Lose Weight Focus
        UserProfile(
            id=5,
            name="Robert Williams",
            age=55,
            gender="Male",
            weight_lbs=220,
            experience_level="Intermediate",
            fitness_goal="Lose Weight",
            available_equipment=["Machines", "Cables"],
            limitations=[
                Limitation("Knees", "be_careful"),
                Limitation("Shoulders", "be_careful")
            ],
            workouts_completed=30,
            preferred_duration_minutes=45,
            selected_muscle_groups=["Legs"],
            focus_areas=["Quadriceps", "Hamstrings", "Glutes"]
        ),
        
        # USER 6: Young Athletic Female - Full Arms
        UserProfile(
            id=6,
            name="Jessica Taylor",
            age=22,
            gender="Female",
            weight_lbs=135,
            experience_level="Intermediate",
            fitness_goal="Build Muscle",
            available_equipment=["Dumbbells", "Cables", "Machines"],
            limitations=[],
            workouts_completed=60,
            preferred_duration_minutes=40,
            selected_muscle_groups=["Arms"],
            focus_areas=["Biceps", "Triceps"]
        ),
        
        # USER 7: Advanced Powerlifter Type
        UserProfile(
            id=7,
            name="Michael Brown",
            age=29,
            gender="Male",
            weight_lbs=210,
            experience_level="Advanced",
            fitness_goal="Get Stronger",
            available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
            limitations=[],
            workouts_completed=200,
            preferred_duration_minutes=60,
            selected_muscle_groups=["Chest", "Shoulders", "Arms"],
            focus_areas=["Upper Chest", "Front Delts", "Triceps"]
        ),
        
        # USER 8: Beginner with Shoulder Issue
        UserProfile(
            id=8,
            name="Amanda Lee",
            age=35,
            gender="Female",
            weight_lbs=155,
            experience_level="Beginner",
            fitness_goal="Improve Health",
            available_equipment=["Machines", "Cables"],
            limitations=[Limitation("Shoulders", "light_only")],
            workouts_completed=5,
            preferred_duration_minutes=30,
            selected_muscle_groups=["Back", "Core"],
            focus_areas=["Lats", "Upper Back", "Upper Abs"]
        ),
        
        # USER 9: Intermediate - Leg Day
        UserProfile(
            id=9,
            name="Chris Martinez",
            age=27,
            gender="Male",
            weight_lbs=175,
            experience_level="Intermediate",
            fitness_goal="Build Muscle",
            available_equipment=["Barbell", "Dumbbells", "Machines", "Cables"],
            limitations=[],
            workouts_completed=75,
            preferred_duration_minutes=50,
            selected_muscle_groups=["Legs"],
            focus_areas=["Quadriceps", "Hamstrings", "Glutes", "Calves"]
        ),
        
        # USER 10: Advanced Female - Push Day
        UserProfile(
            id=10,
            name="Nicole Anderson",
            age=31,
            gender="Female",
            weight_lbs=140,
            experience_level="Advanced",
            fitness_goal="Build Muscle",
            available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
            limitations=[],
            workouts_completed=120,
            preferred_duration_minutes=55,
            selected_muscle_groups=["Chest", "Shoulders"],
            focus_areas=["Upper Chest", "Lower Chest", "Side Delts", "Rear Delts"]
        ),
    ]
    
    return profiles

# ═══════════════════════════════════════════════════════════════════════════════
# EXERCISE LOADING FROM REAL DATABASE
# ═══════════════════════════════════════════════════════════════════════════════

def load_exercises_from_supabase() -> List[Dict]:
    """Load all exercises from the real Supabase database"""
    print("📥 Loading exercises from Supabase...")
    all_exercises = []
    offset = 0
    batch_size = 1000
    
    while True:
        response = supabase.table('exercises').select('*').range(offset, offset + batch_size - 1).execute()
        batch = response.data
        if not batch:
            break
        all_exercises.extend(batch)
        offset += batch_size
        if len(batch) < batch_size:
            break
    
    print(f"✅ Loaded {len(all_exercises)} exercises from database")
    return all_exercises

# ═══════════════════════════════════════════════════════════════════════════════
# REAL WORKOUT GENERATION LOGIC (MIRRORS iOS APP)
# ═══════════════════════════════════════════════════════════════════════════════

# Risky exercises for foundational users (mirrors Swift)
RISKY_EXERCISES = {
    "snatch", "clean and jerk", "clean", "power clean", "hang clean",
    "muscle up", "kipping", "handstand", "pistol squat", "dragon flag",
    "behind the neck", "behind neck", "guillotine press", "sissy squat",
    "jefferson squat", "zercher", "good morning", "straight leg deadlift"
}

# Lower back stress exercises
LOWER_BACK_STRESS = {
    "deadlift", "bent over row", "bent-over row", "barbell row", "t-bar row",
    "good morning", "back extension", "hyperextension", "romanian deadlift",
    "stiff leg", "sumo deadlift", "conventional deadlift"
}

# Foundational exercises (prioritized for beginners)
FOUNDATIONAL_EXERCISES = {
    # Back
    "lat pulldown", "seated cable row", "cable row", "machine row",
    "chest supported row", "lever row", "face pull", "reverse fly",
    "straight arm pulldown", "pull up", "chin up",
    
    # Chest
    "bench press", "chest press", "machine press", "dumbbell press",
    "incline press", "cable fly", "pec deck", "machine fly",
    
    # Shoulders
    "shoulder press", "lateral raise", "machine press", "front raise",
    "rear delt", "face pull", "arnold press",
    
    # Arms
    "bicep curl", "cable curl", "preacher curl", "hammer curl",
    "tricep pushdown", "cable pushdown", "overhead extension",
    "skull crusher", "dip",
    
    # Legs
    "leg press", "squat", "leg extension", "leg curl", "hamstring curl",
    "hip thrust", "lunge", "split squat", "calf raise", "glute bridge",
}

def is_foundational_exercise(name: str) -> bool:
    """Check if exercise is foundational (beginner-friendly)"""
    name_lower = name.lower()
    return any(f in name_lower for f in FOUNDATIONAL_EXERCISES)

def is_risky_exercise(name: str) -> bool:
    """Check if exercise is risky for beginners"""
    name_lower = name.lower()
    return any(r in name_lower for r in RISKY_EXERCISES)

def is_lower_back_stress(name: str) -> bool:
    """Check if exercise stresses lower back"""
    name_lower = name.lower()
    return any(s in name_lower for s in LOWER_BACK_STRESS)

def is_combo_exercise(name: str) -> bool:
    """Check if exercise is a combo move (X to Y pattern)"""
    name_lower = name.lower()
    if " to " in name_lower:
        allowed = ["low to high", "high to low"]
        return not any(a in name_lower for a in allowed)
    return False

def normalize_equipment(equipment: str) -> str:
    """Normalize equipment string for matching"""
    eq = equipment.lower()
    if "cable" in eq: return "cable"
    if "machine" in eq or "lever" in eq or "smith" in eq: return "machine"
    if "barbell" in eq or "ez bar" in eq or "olympic" in eq: return "barbell"
    if "dumbbell" in eq or "db" in eq: return "dumbbell"
    if "body" in eq or "bodyweight" in eq: return "bodyweight"
    if "band" in eq or "resistance" in eq: return "band"
    if "kettlebell" in eq: return "kettlebell"
    return eq

def equipment_matches(exercise_equipment: str, user_equipment: List[str]) -> bool:
    """Check if exercise equipment matches user's available equipment"""
    eq_norm = normalize_equipment(exercise_equipment)
    user_eq_norm = [normalize_equipment(e) for e in user_equipment]
    
    # Bodyweight always available
    if eq_norm == "bodyweight":
        return True
    
    # Direct match
    if eq_norm in user_eq_norm:
        return True
    
    # Machine includes lever/smith
    if eq_norm in ["machine", "lever", "smith"] and "machine" in user_eq_norm:
        return True
    
    return False

def muscle_matches(exercise: Dict, target_muscles: List[str], focus_areas: List[str]) -> bool:
    """Check if exercise targets the requested muscles - STRICT matching"""
    # Get exercise muscles
    primary = (exercise.get('primary_muscles') or [])
    secondary = (exercise.get('secondary_muscles') or [])
    category = (exercise.get('category') or '').lower()
    name = (exercise.get('name') or '').lower()
    
    all_muscles = [m.lower() for m in primary + secondary]
    primary_lower = [m.lower() for m in primary]
    
    # Normalize targets
    targets_lower = [t.lower() for t in target_muscles + focus_areas]
    
    # Strict category-based matching (PRIMARY must match category)
    category_map = {
        "back": ["back", "lats", "upper back", "rhomboids", "traps"],
        "chest": ["chest", "pectorals", "pecs"],
        "shoulders": ["shoulders", "delts", "deltoids", "front delts", "side delts", "rear delts"],
        "arms": ["biceps", "triceps", "forearms", "brachialis"],
        "legs": ["legs", "quadriceps", "hamstrings", "glutes", "calves", "quads"],
        "core": ["core", "abs", "obliques", "abdominals"],
    }
    
    # Check if exercise category matches ANY target
    for target in targets_lower:
        # Direct category match
        if target in category or category in target:
            return True
        
        # Check category map
        for cat_key, cat_muscles in category_map.items():
            if target in cat_muscles or any(target in m for m in cat_muscles):
                if category == cat_key:
                    return True
    
    # Check primary muscles against targets
    for primary_muscle in primary_lower:
        for target in targets_lower:
            # Back targeting
            if target in ["back", "lats", "upper back"]:
                if any(k in primary_muscle for k in ["lat", "back", "rhomboid", "trap"]):
                    return True
            
            # Biceps targeting
            if target == "biceps":
                if any(k in primary_muscle for k in ["bicep", "brachialis"]):
                    return True
            
            # Triceps targeting
            if target == "triceps":
                if "tricep" in primary_muscle:
                    return True
            
            # Chest targeting
            if target in ["chest", "upper chest", "lower chest"]:
                if any(k in primary_muscle for k in ["chest", "pec"]):
                    return True
            
            # Shoulders targeting
            if target in ["shoulders", "front delts", "side delts", "rear delts"]:
                if any(k in primary_muscle for k in ["delt", "shoulder"]):
                    return True
            
            # Legs targeting
            if target in ["legs", "quadriceps", "hamstrings", "glutes", "calves"]:
                if any(k in primary_muscle for k in ["quad", "ham", "glute", "calf", "leg"]):
                    return True
            
            # Core targeting
            if target in ["core", "upper abs", "lower abs"]:
                if any(k in primary_muscle for k in ["ab", "oblique", "core", "rectus"]):
                    return True
    
    # Name-based verification for arms
    if "arms" in targets_lower or "biceps" in targets_lower:
        if any(k in name for k in ["curl", "bicep", "hammer"]) and "leg curl" not in name:
            return True
    
    if "arms" in targets_lower or "triceps" in targets_lower:
        if any(k in name for k in ["tricep", "pushdown", "extension", "skull crusher"]) and "leg" not in name:
            return True
    
    return False

def get_exercise_count(duration_minutes: int) -> int:
    """Get exercise count based on duration (mirrors iOS app)"""
    if duration_minutes <= 20:
        return 4
    elif duration_minutes <= 35:
        return 5
    elif duration_minutes <= 45:
        return 6
    elif duration_minutes <= 55:
        return 7
    else:
        return 8

def score_exercise(exercise: Dict, user: UserProfile, used_patterns: Set[str], 
                   used_families: Set[str], used_equipment: Dict[str, int]) -> float:
    """Score an exercise for selection (mirrors iOS app scoring)"""
    name = exercise.get('name', '').lower()
    equipment = exercise.get('equipment', '')
    score = 100.0
    
    # ═══════════════════════════════════════════════════════════════════════════
    # FOUNDATIONAL BOOST (for users with <10 workouts)
    # ═══════════════════════════════════════════════════════════════════════════
    if user.workouts_completed < 10:
        if is_foundational_exercise(name):
            score += 150
        else:
            score -= 100  # Penalize non-foundational for beginners
        
        # Block risky exercises
        if is_risky_exercise(name):
            return -1000
        
        # Block combo exercises
        if is_combo_exercise(name):
            return -1000
    
    # ═══════════════════════════════════════════════════════════════════════════
    # LIMITATION HANDLING
    # ═══════════════════════════════════════════════════════════════════════════
    for limitation in user.limitations:
        area = limitation.area.lower()
        severity = limitation.severity
        
        if area == "lower back":
            if is_lower_back_stress(name):
                if severity == "skip_completely":
                    return -1000
                elif severity == "light_only":
                    score -= 300
                else:  # be_careful
                    score -= 100
            # Boost supported rows
            if "chest supported" in name or "machine row" in name or "seated cable" in name:
                score += 80
        
        if area == "shoulders":
            if "overhead" in name or "behind neck" in name or "upright row" in name:
                if severity in ["skip_completely", "light_only"]:
                    return -1000
                score -= 150
        
        if area == "knees":
            if "squat" in name or "lunge" in name or "leg press" in name:
                if severity == "skip_completely":
                    return -1000
                score -= 100
    
    # ═══════════════════════════════════════════════════════════════════════════
    # EQUIPMENT QUALITY BOOST (not equipment-as-difficulty!)
    # ═══════════════════════════════════════════════════════════════════════════
    eq_norm = normalize_equipment(equipment)
    
    if eq_norm == "cable":
        score += 40  # Constant tension, great for isolation
    elif eq_norm == "machine":
        score += 40  # Stable, great for compounds
    elif eq_norm == "dumbbell":
        score += 30  # Unilateral, natural ROM
    elif eq_norm == "barbell":
        score += 35  # Heavy bilateral compounds
    
    # Supported rows get bonus when back is target
    if any("back" in t.lower() or "lat" in t.lower() for t in user.selected_muscle_groups):
        if "chest supported" in name or "machine row" in name or "seated cable" in name:
            score += 60
    
    # ═══════════════════════════════════════════════════════════════════════════
    # PATTERN REQUIREMENTS (from combo rules)
    # ═══════════════════════════════════════════════════════════════════════════
    if COMBO_RULES_AVAILABLE:
        pattern = detect_exercise_pattern(name, equipment)
        
        # Boost if we need this pattern
        combo_key = detect_workout_combo(user.selected_muscle_groups + user.focus_areas)
        if combo_key:
            rule = get_combo_rule(combo_key)
            if rule and 'must_include' in rule:
                if pattern in rule['must_include'] and pattern not in used_patterns:
                    score += 100  # Need this pattern!
    
    # ═══════════════════════════════════════════════════════════════════════════
    # VARIETY (prevent duplicates)
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Family detection
    family = "other"
    if "bench press" in name: family = "bench_press"
    elif "incline press" in name: family = "incline_press"
    elif "pulldown" in name or "lat pull" in name: family = "lat_pulldown"
    elif "row" in name: family = "row"
    elif "curl" in name and "leg" not in name: family = "curl"
    elif "extension" in name and "tricep" in name: family = "tricep_extension"
    elif "pushdown" in name: family = "pushdown"
    elif "fly" in name: family = "fly"
    elif "raise" in name: family = "raise"
    elif "squat" in name: family = "squat"
    elif "press" in name: family = "press"
    
    if family in used_families:
        score -= 200  # Already have this family
    
    # Equipment diversity
    eq_count = used_equipment.get(eq_norm, 0)
    if eq_count >= 2:
        score -= 50  # Too much of one equipment type
    
    return score

def generate_workout(exercises: List[Dict], user: UserProfile) -> List[Dict]:
    """
    Generate a workout using REAL selection logic (mirrors iOS app).
    This is the same algorithm used in WorkoutGeneratorService.swift
    """
    count = get_exercise_count(user.preferred_duration_minutes)
    target_muscles = user.selected_muscle_groups + user.focus_areas
    targets_lower = [t.lower() for t in target_muscles]
    
    # Determine what we're targeting for strict filtering
    wants_back = any(t in ["back", "lats", "upper back"] for t in targets_lower)
    wants_biceps = "biceps" in targets_lower
    wants_triceps = "triceps" in targets_lower
    wants_chest = any(t in ["chest", "upper chest", "lower chest"] for t in targets_lower)
    wants_shoulders = any(t in ["shoulders", "front delts", "side delts", "rear delts"] for t in targets_lower)
    wants_legs = any(t in ["legs", "quadriceps", "hamstrings", "glutes", "calves"] for t in targets_lower)
    wants_core = any(t in ["core", "upper abs", "lower abs"] for t in targets_lower)
    wants_arms = "arms" in targets_lower or wants_biceps or wants_triceps
    
    # Filter exercises
    candidates = []
    for ex in exercises:
        name = ex.get('name', '').lower()
        equipment = ex.get('equipment', '')
        category = ex.get('category', '').lower()
        
        # Equipment filter
        if not equipment_matches(equipment, user.available_equipment):
            continue
        
        # ═══════════════════════════════════════════════════════════════════════════
        # STRICT CATEGORY FILTERING - Block wrong categories entirely
        # ═══════════════════════════════════════════════════════════════════════════
        
        # If targeting Back + Arms, block legs/core/chest/shoulders
        if wants_back and wants_arms and not wants_chest and not wants_shoulders and not wants_legs:
            if category in ["legs", "cardio"]:
                continue
            # Block chest/shoulder presses
            if category == "chest" and "press" in name:
                continue
            if category == "shoulders" and not ("rear delt" in name or "face pull" in name or "reverse fly" in name):
                continue
        
        # If targeting Chest + Shoulders, block back/legs exercises
        if wants_chest and wants_shoulders and not wants_back and not wants_legs:
            if category in ["legs", "back", "cardio"]:
                continue
        
        # If targeting Legs only, block upper body
        if wants_legs and not wants_back and not wants_chest and not wants_shoulders and not wants_arms:
            if category in ["chest", "back", "shoulders", "arms", "cardio"]:
                continue
        
        # If targeting Arms only, block legs/cardio
        if wants_arms and not wants_back and not wants_chest and not wants_shoulders and not wants_legs:
            if category in ["legs", "cardio"]:
                continue
        
        # Muscle filter
        if not muscle_matches(ex, user.selected_muscle_groups, user.focus_areas):
            continue
        
        # Block triceps if not targeting triceps (for Back + Biceps)
        if wants_biceps and not wants_triceps:
            if any(k in name for k in ["tricep", "pushdown", "skull crusher"]) or \
               (category == "arms" and "extension" in name and "back" not in name):
                continue
        
        # Block kickbacks/glute exercises if not targeting legs
        if not wants_legs:
            if "kickback" in name and "tricep" not in name:
                continue
            if "glute" in name:
                continue
        
        candidates.append(ex)
    
    print(f"   📋 {len(candidates)} candidate exercises after filtering")
    
    # Score and select
    selected = []
    used_names = set()
    used_patterns = set()
    used_families = set()
    used_equipment = {}
    
    # Get required patterns from combo rules
    required_patterns = []
    if COMBO_RULES_AVAILABLE:
        combo_key = detect_workout_combo(target_muscles)
        if combo_key:
            rule = get_combo_rule(combo_key)
            if rule and 'must_include' in rule:
                required_patterns = rule['must_include']
                print(f"   🎯 Required patterns: {required_patterns}")
    
    # Phase 1: Fulfill required patterns first
    for required in required_patterns:
        if len(selected) >= count:
            break
        
        best_score = -1000
        best_ex = None
        
        for ex in candidates:
            name = ex.get('name', '').lower()
            equipment = ex.get('equipment', '')
            
            if name in used_names:
                continue
            
            # Check pattern match
            if COMBO_RULES_AVAILABLE:
                pattern = detect_exercise_pattern(name, equipment)
                # Handle aliases
                matches = pattern == required
                if required == "horizontal_row" and pattern in ["horizontal_row", "chest_supported_row"]:
                    matches = True
                if required == "bicep_curl" and pattern in ["bicep_curl", "bicep_neutral", "bicep_preacher"]:
                    matches = True
                
                if not matches:
                    continue
            
            score = score_exercise(ex, user, used_patterns, used_families, used_equipment)
            if score > best_score:
                best_score = score
                best_ex = ex
        
        if best_ex:
            selected.append(best_ex)
            name = best_ex.get('name', '').lower()
            used_names.add(name)
            used_patterns.add(required)
            
            # Track family
            family = "other"
            if "bench press" in name: family = "bench_press"
            elif "pulldown" in name: family = "lat_pulldown"
            elif "row" in name: family = "row"
            elif "curl" in name: family = "curl"
            elif "fly" in name: family = "fly"
            elif "press" in name: family = "press"
            used_families.add(family)
            
            # Track equipment
            eq_norm = normalize_equipment(best_ex.get('equipment', ''))
            used_equipment[eq_norm] = used_equipment.get(eq_norm, 0) + 1
    
    # Phase 2: Fill remaining slots with best scored exercises
    scored_candidates = []
    for ex in candidates:
        name = ex.get('name', '').lower()
        if name in used_names:
            continue
        
        score = score_exercise(ex, user, used_patterns, used_families, used_equipment)
        if score > -500:  # Skip heavily penalized
            scored_candidates.append((score, ex))
    
    scored_candidates.sort(key=lambda x: x[0], reverse=True)
    
    for score, ex in scored_candidates:
        if len(selected) >= count:
            break
        
        name = ex.get('name', '').lower()
        
        # Family check
        family = "other"
        if "bench press" in name: family = "bench_press"
        elif "pulldown" in name: family = "lat_pulldown"
        elif "row" in name: family = "row"
        elif "curl" in name: family = "curl"
        elif "fly" in name: family = "fly"
        elif "press" in name: family = "press"
        
        if family != "other" and family in used_families:
            continue
        
        selected.append(ex)
        used_names.add(name)
        used_families.add(family)
        
        eq_norm = normalize_equipment(ex.get('equipment', ''))
        used_equipment[eq_norm] = used_equipment.get(eq_norm, 0) + 1
    
    return selected

# ═══════════════════════════════════════════════════════════════════════════════
# PDF GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

def generate_pdf(users: List[UserProfile], workouts: Dict[int, List[Dict]], output_path: str):
    """Generate clean PDF report"""
    
    doc = SimpleDocTemplate(output_path, pagesize=letter,
                           leftMargin=0.75*inch, rightMargin=0.75*inch,
                           topMargin=0.5*inch, bottomMargin=0.5*inch)
    
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'Title',
        parent=styles['Heading1'],
        fontSize=24,
        alignment=TA_CENTER,
        spaceAfter=30,
        textColor=colors.HexColor('#1a1a2e')
    )
    
    heading_style = ParagraphStyle(
        'Heading',
        parent=styles['Heading2'],
        fontSize=16,
        textColor=colors.HexColor('#16213e'),
        spaceBefore=15,
        spaceAfter=10
    )
    
    subheading_style = ParagraphStyle(
        'Subheading',
        parent=styles['Heading3'],
        fontSize=12,
        textColor=colors.HexColor('#0f3460'),
        spaceBefore=10,
        spaceAfter=5
    )
    
    normal_style = ParagraphStyle(
        'Normal',
        parent=styles['Normal'],
        fontSize=10,
        leading=14
    )
    
    story = []
    
    # Title Page
    story.append(Spacer(1, 100))
    story.append(Paragraph("FIT33 AUTO-GEN AUDIT", title_style))
    story.append(Paragraph("10 User Profiles • Real Workout Generation", 
                          ParagraphStyle('Subtitle', parent=normal_style, 
                                        fontSize=14, alignment=TA_CENTER, textColor=colors.grey)))
    story.append(Spacer(1, 30))
    story.append(Paragraph(f"Generated: {datetime.now().strftime('%B %d, %Y at %I:%M %p')}", 
                          ParagraphStyle('Date', parent=normal_style, 
                                        alignment=TA_CENTER, textColor=colors.grey)))
    story.append(Spacer(1, 20))
    story.append(Paragraph("This report uses REAL exercise data from the Supabase database<br/>"
                          "and the SAME selection logic as the iOS app.",
                          ParagraphStyle('Note', parent=normal_style, 
                                        alignment=TA_CENTER, fontSize=10, textColor=colors.grey)))
    story.append(PageBreak())
    
    # Each user
    for user in users:
        workout = workouts.get(user.id, [])
        
        # User Header
        story.append(Paragraph(f"USER {user.id}: {user.name}", heading_style))
        
        # Profile Table
        profile_data = [
            ["Age", str(user.age), "Gender", user.gender],
            ["Weight", f"{user.weight_lbs} lbs", "Experience", user.experience_level],
            ["Goal", user.fitness_goal, "Workouts Done", str(user.workouts_completed)],
            ["Duration", f"{user.preferred_duration_minutes} min", "Equipment", ", ".join(user.available_equipment)],
        ]
        
        if user.limitations:
            lim_str = ", ".join([f"{l.area} ({l.severity})" for l in user.limitations])
            profile_data.append(["Limitations", lim_str, "", ""])
        
        profile_table = Table(profile_data, colWidths=[80, 130, 80, 140])
        profile_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#e8e8e8')),
            ('BACKGROUND', (2, 0), (2, -1), colors.HexColor('#e8e8e8')),
            ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
            ('FONTNAME', (2, 0), (2, -1), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, -1), 9),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
            ('LEFTPADDING', (0, 0), (-1, -1), 5),
            ('RIGHTPADDING', (0, 0), (-1, -1), 5),
        ]))
        story.append(profile_table)
        story.append(Spacer(1, 15))
        
        # Auto-Gen Input
        story.append(Paragraph("AUTO-GEN INPUT", subheading_style))
        input_text = f"<b>Selected Groups:</b> {', '.join(user.selected_muscle_groups)}<br/>"
        input_text += f"<b>Focus Areas:</b> {', '.join(user.focus_areas)}"
        story.append(Paragraph(input_text, normal_style))
        story.append(Spacer(1, 15))
        
        # Generated Workout
        story.append(Paragraph("GENERATED WORKOUT", subheading_style))
        
        if workout:
            ex_data = [["#", "Exercise Name", "Equipment", "Primary Muscles"]]
            for i, ex in enumerate(workout, 1):
                name = ex.get('name', 'Unknown')
                equipment = ex.get('equipment', 'Unknown')
                primary = ", ".join(ex.get('primary_muscles', [])[:2]) or "N/A"
                ex_data.append([str(i), name, equipment, primary])
            
            ex_table = Table(ex_data, colWidths=[25, 230, 100, 100])
            ex_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1a1a2e')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
                ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, -1), 9),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                ('ALIGN', (0, 0), (0, -1), 'CENTER'),
                ('LEFTPADDING', (0, 0), (-1, -1), 4),
                ('RIGHTPADDING', (0, 0), (-1, -1), 4),
            ]))
            story.append(ex_table)
        else:
            story.append(Paragraph("❌ No workout generated (validation failed)", 
                                  ParagraphStyle('Error', parent=normal_style, textColor=colors.red)))
        
        story.append(Spacer(1, 10))
        
        # Pattern Analysis
        if workout and COMBO_RULES_AVAILABLE:
            story.append(Paragraph("PATTERN ANALYSIS", subheading_style))
            patterns_found = []
            for ex in workout:
                pattern = detect_exercise_pattern(ex.get('name', ''), ex.get('equipment', ''))
                patterns_found.append(pattern)
            
            pattern_text = f"<b>Detected Patterns:</b> {', '.join(set(patterns_found))}"
            story.append(Paragraph(pattern_text, normal_style))
        
        story.append(PageBreak())
    
    # Build PDF
    doc.build(story)
    print(f"\n📄 PDF saved to: {output_path}")

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    print("=" * 80)
    print("🏋️ FIT33 AUTO-GEN AUDIT - 10 USER PROFILES")
    print("=" * 80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Load REAL exercises from Supabase
    exercises = load_exercises_from_supabase()
    
    if not exercises:
        print("❌ Failed to load exercises from database!")
        return
    
    # Create user profiles
    print("\n📋 Creating 10 diverse user profiles...")
    users = create_10_user_profiles()
    print(f"✅ Created {len(users)} user profiles")
    
    # Generate workouts for each user
    print("\n🏋️ Generating workouts...")
    workouts = {}
    
    for user in users:
        print(f"\n👤 User {user.id}: {user.name}")
        print(f"   Profile: {user.experience_level}, {user.fitness_goal}")
        print(f"   Target: {user.selected_muscle_groups} → {user.focus_areas}")
        
        workout = generate_workout(exercises, user)
        workouts[user.id] = workout
        
        print(f"   ✅ Generated {len(workout)} exercises:")
        for i, ex in enumerate(workout, 1):
            print(f"      {i}. {ex.get('name', 'Unknown')} ({ex.get('equipment', '')})")
    
    # Generate PDF
    output_path = os.path.join(os.path.dirname(__file__), 
                               f"10_user_autogen_audit_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf")
    generate_pdf(users, workouts, output_path)
    
    print("\n" + "=" * 80)
    print("✅ AUDIT COMPLETE")
    print("=" * 80)

if __name__ == "__main__":
    main()
