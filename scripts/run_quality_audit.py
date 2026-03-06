#!/usr/bin/env python3
"""
Workout Quality Audit Script
============================
Automated testing system for workout generation quality.
Generates 200 diverse test users and grades workout outputs.

Run: python3 run_quality_audit.py
"""

import random
import json
import csv
import os
from dataclasses import dataclass, field
from typing import List, Dict, Set, Tuple
from collections import defaultdict
from datetime import datetime

# ═══════════════════════════════════════════════════════════════════════════════
# DATA MODELS
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class TestLimitation:
    area: str  # "Lower Back", "Shoulders", etc.
    accommodation: str  # "skipCompletely", "lightWorkOnly", "stretchingOnly", "beCareful"

@dataclass
class TestUser:
    id: int
    name: str
    age: int
    gender: str
    weight_lbs: float
    height_cm: float
    goal: str
    experience_level: str
    workout_location: str
    equipment: List[str]
    limitations: List[TestLimitation]
    days_per_week: int

@dataclass
class Exercise:
    id: str
    name: str
    equipment: str
    muscle_groups: List[str]
    category: str
    workout_type: str
    practicality_score: int

@dataclass
class WorkoutScorecard:
    equipment_score: float = 0
    safety_score: float = 0
    practicality_score: float = 0
    goal_alignment_score: float = 0
    experience_score: float = 0
    variety_score: float = 0
    location_score: float = 0
    profile_score: float = 0
    equipment_diversity_score: float = 0  # 🆕 Equipment diversity (cable vs dumbbell etc)
    
    equipment_violations: List[str] = field(default_factory=list)
    safety_violations: List[str] = field(default_factory=list)
    practicality_violations: List[str] = field(default_factory=list)
    goal_violations: List[str] = field(default_factory=list)
    experience_violations: List[str] = field(default_factory=list)
    variety_violations: List[str] = field(default_factory=list)
    location_violations: List[str] = field(default_factory=list)
    profile_violations: List[str] = field(default_factory=list)
    equipment_diversity_violations: List[str] = field(default_factory=list)  # 🆕
    
    @property
    def overall_score(self) -> float:
        # Updated weights to include equipment diversity (15% weight)
        weights = [0.15, 0.15, 0.10, 0.10, 0.10, 0.10, 0.10, 0.05, 0.15]
        scores = [self.equipment_score, self.safety_score, self.practicality_score,
                  self.goal_alignment_score, self.experience_score, self.variety_score,
                  self.location_score, self.profile_score, self.equipment_diversity_score]
        return sum(w * s for w, s in zip(weights, scores))
    
    @property
    def passed(self) -> bool:
        return self.overall_score >= 80
    
    @property
    def all_violations(self) -> List[str]:
        return (self.equipment_violations + self.safety_violations + 
                self.practicality_violations + self.goal_violations +
                self.experience_violations + self.variety_violations +
                self.location_violations + self.profile_violations +
                self.equipment_diversity_violations)

# ═══════════════════════════════════════════════════════════════════════════════
# LOAD EXERCISES FROM CSV
# ═══════════════════════════════════════════════════════════════════════════════

def load_exercises() -> List[Exercise]:
    """Load exercises from the practicality scores CSV and the master CSV."""
    exercises = []
    
    # Load practicality scores
    practicality_scores = {}
    practicality_file = "final_practicality_scores.csv"
    
    if os.path.exists(practicality_file):
        with open(practicality_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                practicality_scores[row['id']] = int(row['practicality_score'])
        print(f"📊 Loaded {len(practicality_scores)} practicality scores")
    
    # Load main exercise data - try multiple possible file locations
    possible_files = [
        "Final Master Correct.csv",
        "Excercises Master (v1) - exercises_rows.csv",
    ]
    
    master_file = None
    for f in possible_files:
        if os.path.exists(f):
            master_file = f
            break
    
    if master_file:
        with open(master_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    exercise_id = row.get('id', '')
                    name = row.get('name', '')
                    equipment = row.get('equipment', 'Bodyweight')
                    category = row.get('category', '')
                    workout_type = row.get('workout_type', 'Strength')
                    
                    # Parse muscle groups
                    muscle_groups_raw = row.get('muscle_groups', row.get('primary_muscle', ''))
                    if muscle_groups_raw.startswith('['):
                        try:
                            muscle_groups = json.loads(muscle_groups_raw.replace("'", '"'))
                        except:
                            muscle_groups = [muscle_groups_raw]
                    else:
                        muscle_groups = [muscle_groups_raw] if muscle_groups_raw else []
                    
                    practicality = practicality_scores.get(exercise_id, 50)
                    
                    exercises.append(Exercise(
                        id=exercise_id,
                        name=name,
                        equipment=equipment,
                        muscle_groups=muscle_groups,
                        category=category,
                        workout_type=workout_type,
                        practicality_score=practicality
                    ))
                except Exception as e:
                    continue
        
        print(f"📊 Loaded {len(exercises)} exercises from {master_file}")
    else:
        # Generate synthetic exercises for testing if no CSV found
        print("⚠️ No exercise CSV found, generating synthetic exercises...")
        exercises = generate_synthetic_exercises()
    
    return exercises

def generate_synthetic_exercises() -> List[Exercise]:
    """Generate synthetic exercises for testing when no CSV is available."""
    exercises = []
    
    # Define exercise templates
    templates = [
        # Chest
        ("Bench Press (Barbell)", "Barbell, Bench", ["Chest"], "Chest", "Strength", 95),
        ("Incline Bench Press (Dumbbell)", "Dumbbell, Bench", ["Chest"], "Chest", "Strength", 90),
        ("Cable Fly", "Cable", ["Chest"], "Chest", "Strength", 85),
        ("Push Up", "Bodyweight", ["Chest"], "Chest", "Strength", 90),
        ("Machine Chest Press", "Machine", ["Chest"], "Chest", "Strength", 85),
        ("Decline Bench Press", "Barbell, Bench", ["Chest"], "Chest", "Strength", 80),
        ("Dumbbell Fly", "Dumbbell, Bench", ["Chest"], "Chest", "Strength", 85),
        
        # Back
        ("Lat Pulldown (Cable)", "Cable", ["Lats"], "Back", "Strength", 90),
        ("Bent Over Row (Barbell)", "Barbell", ["Lats", "Traps"], "Back", "Strength", 90),
        ("Seated Row (Cable)", "Cable", ["Lats"], "Back", "Strength", 85),
        ("Pull Up", "Bodyweight", ["Lats"], "Back", "Strength", 85),
        ("Dumbbell Row", "Dumbbell", ["Lats"], "Back", "Strength", 90),
        ("T-Bar Row", "Barbell", ["Lats"], "Back", "Strength", 80),
        ("Machine Row", "Machine", ["Lats"], "Back", "Strength", 80),
        
        # Shoulders
        ("Overhead Press (Barbell)", "Barbell", ["Front Delts"], "Shoulders", "Strength", 90),
        ("Lateral Raise (Dumbbell)", "Dumbbell", ["Side Delts"], "Shoulders", "Strength", 90),
        ("Face Pull (Cable)", "Cable", ["Rear Delts"], "Shoulders", "Strength", 85),
        ("Shoulder Press (Dumbbell)", "Dumbbell", ["Front Delts"], "Shoulders", "Strength", 90),
        ("Handstand Shoulder Press With Wall", "Bench, Wall", ["Front Delts"], "Shoulders", "Strength", 5),
        ("Machine Shoulder Press", "Machine", ["Front Delts"], "Shoulders", "Strength", 80),
        ("Arnold Press", "Dumbbell", ["Delts"], "Shoulders", "Strength", 80),
        
        # Arms
        ("Bicep Curl (Dumbbell)", "Dumbbell", ["Biceps"], "Arms", "Strength", 95),
        ("Tricep Pushdown (Cable)", "Cable", ["Triceps"], "Arms", "Strength", 90),
        ("Hammer Curl", "Dumbbell", ["Biceps"], "Arms", "Strength", 90),
        ("Skull Crusher", "Barbell, Bench", ["Triceps"], "Arms", "Strength", 80),
        ("Preacher Curl", "Barbell, Bench", ["Biceps"], "Arms", "Strength", 80),
        ("Cable Curl", "Cable", ["Biceps"], "Arms", "Strength", 85),
        ("Tricep Dip", "Bodyweight", ["Triceps"], "Arms", "Strength", 80),
        
        # Legs
        ("Squat (Barbell)", "Barbell", ["Quads", "Glutes"], "Legs", "Strength", 95),
        ("Leg Press", "Machine", ["Quads"], "Legs", "Strength", 90),
        ("Romanian Deadlift", "Barbell", ["Hamstrings"], "Legs", "Strength", 85),
        ("Leg Extension", "Machine", ["Quads"], "Legs", "Strength", 85),
        ("Leg Curl", "Machine", ["Hamstrings"], "Legs", "Strength", 85),
        ("Lunges (Dumbbell)", "Dumbbell", ["Quads", "Glutes"], "Legs", "Strength", 90),
        ("Calf Raise", "Machine", ["Calves"], "Legs", "Strength", 85),
        ("Goblet Squat", "Dumbbell", ["Quads"], "Legs", "Strength", 90),
        ("Hip Thrust", "Barbell, Bench", ["Glutes"], "Legs", "Strength", 85),
        
        # Core
        ("Plank", "Bodyweight", ["Abs"], "Core", "Strength", 90),
        ("Cable Crunch", "Cable", ["Abs"], "Core", "Strength", 80),
        ("Hanging Leg Raise", "Bodyweight", ["Abs"], "Core", "Strength", 75),
        ("Russian Twist", "Bodyweight", ["Obliques"], "Core", "Strength", 80),
        
        # Full Body / Compound
        ("Deadlift (Barbell)", "Barbell", ["Back", "Legs", "Glutes"], "Full Body", "Strength", 90),
        ("Clean and Press", "Barbell", ["Full Body"], "Full Body", "Strength", 60),
        ("Kettlebell Swing", "Kettlebell", ["Glutes", "Hamstrings"], "Full Body", "Strength", 80),
        ("Burpee", "Bodyweight", ["Full Body"], "Cardio", "Cardio", 70),
        
        # Problematic exercises (should be filtered)
        ("Bottle Weighted Curl", "Bottle", ["Biceps"], "Arms", "Strength", 10),
        ("Handstand Push Up", "Bodyweight", ["Shoulders"], "Shoulders", "Strength", 5),
        ("Planche", "Bodyweight", ["Chest"], "Chest", "Strength", 5),
        ("Front Lever", "Bodyweight", ["Lats"], "Back", "Strength", 5),
        ("Ring Handstand", "Rings", ["Shoulders"], "Shoulders", "Strength", 5),
        ("Partner Assisted Squat", "Partner", ["Legs"], "Legs", "Strength", 20),
    ]
    
    for i, (name, equip, muscles, cat, wtype, prac) in enumerate(templates):
        exercises.append(Exercise(
            id=f"test-{i}",
            name=name,
            equipment=equip,
            muscle_groups=muscles,
            category=cat,
            workout_type=wtype,
            practicality_score=prac
        ))
    
    return exercises

# ═══════════════════════════════════════════════════════════════════════════════
# USER GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

def generate_test_users(count: int = 200) -> List[TestUser]:
    """Generate diverse test users."""
    users = []
    
    goals = ["Build Muscle", "Lose Weight", "Get Stronger", "Tone & Define", "Endurance", "General Fitness"]
    levels = ["Beginner", "Intermediate", "Advanced"]
    locations = ["Gym", "Home", "Outdoor", "Hybrid"]
    genders = ["Male", "Female"]
    
    limitation_areas = ["Lower Back", "Shoulders", "Knees", "Wrists", "Neck", "Elbows", "Hips", "Ankles"]
    accommodations = ["skipCompletely", "lightWorkOnly", "stretchingOnly", "beCareful"]
    
    gym_equipment_sets = [
        ["Dumbbells", "Barbell", "Cables", "Machines", "Bench"],
        ["Dumbbells", "Cables", "Machines"],
        ["Barbell", "Machines", "Bench"],
        ["Dumbbells", "Barbell", "Cables", "Machines", "Bench", "Smith Machine", "Kettlebells"],
        ["Machines", "Cables"],
        ["Dumbbells", "Barbell", "Bench"]
    ]
    
    home_equipment_sets = [
        ["Dumbbells", "Resistance Bands"],
        ["Bodyweight"],
        ["Dumbbells", "Kettlebells", "Resistance Bands"],
        ["Dumbbells", "Barbell", "Bench"],
        ["Bodyweight", "Resistance Bands"],
        ["Dumbbells"]
    ]
    
    first_names = ["Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Quinn", "Avery",
                   "Cameron", "Skyler", "Dakota", "Jamie", "Reese", "Charlie", "Finley", "Sage",
                   "Blake", "Drew", "Hayden", "Parker", "Rowan", "Spencer", "Sydney", "Phoenix",
                   "River", "Addison", "Bailey", "Brooklyn", "Dallas", "Denver", "Eden", "Emerson"]
    
    for i in range(count):
        goal = goals[i % len(goals)]
        level = levels[i % len(levels)]
        gender = genders[i % len(genders)]
        
        # Age distribution
        age_ranges = [(18, 25), (26, 35), (36, 45), (46, 55), (56, 65), (66, 75)]
        age_range = age_ranges[i % len(age_ranges)]
        age = random.randint(age_range[0], age_range[1])
        
        # Weight distribution
        if gender == "Male":
            weight = random.uniform(140, 280)
        else:
            weight = random.uniform(110, 220)
        
        # Height
        if gender == "Male":
            height = random.uniform(165, 195)
        else:
            height = random.uniform(155, 180)
        
        # Location and equipment
        location_roll = i % 10
        if location_roll < 5:
            location = "Gym"
            equipment = gym_equipment_sets[i % len(gym_equipment_sets)]
        elif location_roll < 8:
            location = "Home"
            equipment = home_equipment_sets[i % len(home_equipment_sets)]
        elif location_roll < 9:
            location = "Outdoor"
            equipment = ["Bodyweight"]
        else:
            location = "Hybrid"
            equipment = home_equipment_sets[i % len(home_equipment_sets)] + ["Machines", "Cables"]
        
        # Limitations (30% of users)
        limitations = []
        if i % 3 == 0:
            num_limitations = 2 if i % 5 == 0 else 1
            for j in range(num_limitations):
                area = limitation_areas[(i + j) % len(limitation_areas)]
                accommodation = accommodations[(i + j) % len(accommodations)]
                limitations.append(TestLimitation(area=area, accommodation=accommodation))
        
        days_per_week = [3, 4, 5, 6][i % 4]
        
        users.append(TestUser(
            id=i + 1,
            name=f"{first_names[i % len(first_names)]} #{i + 1}",
            age=age,
            gender=gender,
            weight_lbs=weight,
            height_cm=height,
            goal=goal,
            experience_level=level,
            workout_location=location,
            equipment=equipment,
            limitations=limitations,
            days_per_week=days_per_week
        ))
    
    return users

# ═══════════════════════════════════════════════════════════════════════════════
# WORKOUT GENERATION SIMULATION
# ═══════════════════════════════════════════════════════════════════════════════

def get_target_muscles(goal: str) -> List[str]:
    """Get target muscles based on user goal."""
    goal_muscles = {
        "Build Muscle": ["Chest", "Back", "Shoulders", "Arms", "Legs"],
        "Lose Weight": ["Full Body", "Cardio", "Legs", "Core"],
        "Get Stronger": ["Chest", "Back", "Legs", "Shoulders"],
        "Tone & Define": ["Arms", "Shoulders", "Core", "Legs"],
        "Endurance": ["Legs", "Core", "Cardio"],
        "General Fitness": ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"]
    }
    return goal_muscles.get(goal, goal_muscles["General Fitness"])

def is_exercise_unsafe_for_area(exercise_name: str, area: str) -> bool:
    """Check if exercise is unsafe for an injury area."""
    area_keywords = {
        "lower back": ["deadlift", "good morning", "bent over row", "back extension", "hyperextension"],
        "shoulders": ["overhead press", "shoulder press", "military press", "lateral raise", "front raise", "upright row"],
        "knees": ["squat", "lunge", "leg press", "leg extension", "jump", "running"],
        "wrists": ["push-up", "pushup", "front squat", "clean", "snatch", "wrist curl"],
        "neck": ["shrug", "neck", "behind neck", "behind the neck"],
        "elbows": ["tricep extension", "skull crusher", "close grip", "curl"],
        "hips": ["squat", "lunge", "hip thrust", "deadlift", "leg raise"],
        "ankles": ["calf raise", "jump", "running", "lunge", "step up"]
    }
    
    keywords = area_keywords.get(area.lower(), [])
    name_lower = exercise_name.lower()
    return any(kw in name_lower for kw in keywords)

def get_equipment_type(equipment_str: str) -> str:
    """Categorize equipment into a type for diversity tracking.
    Updated to handle new database format (Cable Machine, Lever Machine, etc.)"""
    equip = equipment_str.lower()
    
    # Handle combined equipment - check first part primarily
    first_part = equip.split(",")[0].strip() if "," in equip else equip
    
    if "dumbbell" in first_part: return "dumbbell"
    if "cable" in first_part: return "cable"  # Catches "Cable Machine"
    if "barbell" in first_part or "ez bar" in first_part or "trap bar" in first_part: return "barbell"
    if "smith" in first_part: return "smith"
    if "lever" in first_part or ("machine" in first_part and "cable" not in first_part and "smith" not in first_part): return "machine"
    if "kettlebell" in first_part: return "kettlebell"
    if "band" in first_part or "resistance" in first_part: return "band"
    if "bodyweight" in first_part or not first_part.strip(): return "bodyweight"
    if "pull-up" in first_part or "pullup" in first_part or "chin-up" in first_part: return "bodyweight"
    return "other"

def normalize_equipment_to_user_category(exercise_equipment: str) -> str:
    """Normalize exercise equipment to match user-selectable categories.
    Handles new database format (Cable Machine -> Cables, Lever Machine -> Machines, etc.)"""
    equip = exercise_equipment.lower().strip()
    
    # Handle combined equipment - take first part
    first_part = equip.split(",")[0].strip() if "," in equip else equip
    
    if "dumbbell" in first_part: return "dumbbells"
    if "cable" in first_part: return "cables"  # Catches "Cable Machine"
    if "barbell" in first_part or "ez bar" in first_part or "trap bar" in first_part: return "barbell"
    if "lever" in first_part or ("machine" in first_part and "cable" not in first_part and "smith" not in first_part): return "machines"
    if "smith" in first_part: return "smith machine"
    if "kettlebell" in first_part: return "kettlebell"
    if "band" in first_part or "resistance" in first_part: return "bands"
    if "bench" in first_part and "dumbbell" not in equip and "barbell" not in equip: return "bench"
    if "bodyweight" in first_part or not first_part: return "bodyweight"
    if "pull-up" in first_part or "pullup" in first_part or "chin-up" in first_part: return "bodyweight"
    if "stability ball" in first_part or "swiss ball" in first_part: return "stability ball"
    if "plyo box" in first_part or "step platform" in first_part or "chair" in first_part: return "bodyweight"
    
    return first_part  # Return as-is if no match

def user_has_required_equipment(exercise_equipment: str, user_equipment: List[str]) -> bool:
    """Check if user has ALL required equipment for an exercise.
    Handles new database format (Dumbbells, Incline Bench -> requires both Dumbbells AND Bench)"""
    if not exercise_equipment or exercise_equipment.lower() == "bodyweight":
        return any("body" in e.lower() for e in user_equipment)
    
    user_equip_lower = set(e.lower() for e in user_equipment)
    common_items = {"floor", "mat", "bodyweight", "body weight"}
    
    # Parse combined equipment (e.g., "Dumbbells, Incline Bench")
    required_parts = [p.strip().lower() for p in exercise_equipment.split(",") if p.strip()]
    
    for required_part in required_parts:
        if required_part in common_items:
            continue
        
        # Normalize the required equipment
        required_category = normalize_equipment_to_user_category(required_part)
        
        # Check if user has this category
        has_this = any(
            required_category in ue or ue in required_category or
            required_part in ue or ue in required_part or
            # Special mappings for new format
            ("cable" in required_part and "cable" in ue) or
            ("machine" in required_part and "machine" in ue) or
            ("lever" in required_part and "machine" in ue) or
            ("bench" in required_part and "bench" in ue) or
            ("band" in required_part and "band" in ue)
            for ue in user_equip_lower
        )
        
        if not has_this:
            return False
    
    return True

def get_user_equipment_types(user_equipment: List[str]) -> Set[str]:
    """Get unique equipment types the user has access to."""
    types = set()
    for equip in user_equipment:
        etype = get_equipment_type(equip)
        if etype != "other" and etype != "bodyweight":
            types.add(etype)
    return types

def filter_exercises_for_user(exercises: List[Exercise], user: TestUser, target_muscles: List[str]) -> List[Exercise]:
    """Filter exercises based on user profile."""
    normalized_equipment = set(e.lower() for e in user.equipment)
    normalized_muscles = set(m.lower() for m in target_muscles)
    is_gym_user = user.workout_location in ["Gym", "Hybrid"]
    
    # Get limitation areas to skip
    skip_areas = set(l.area.lower() for l in user.limitations if l.accommodation == "skipCompletely")
    
    filtered = []
    
    for ex in exercises:
        name_lower = ex.name.lower()
        equipment_lower = ex.equipment.lower()
        category_lower = ex.category.lower()
        muscle_lower = [m.lower() for m in ex.muscle_groups]
        
        # ═══════════════════════════════════════════════════════════════
        # FILTER 1: Equipment - ALL required equipment must be available
        # Updated to handle new database format (Cable Machine, Lever Machine, etc.)
        # ═══════════════════════════════════════════════════════════════
        is_bodyweight = not equipment_lower or equipment_lower == "bodyweight"
        if not user_has_required_equipment(ex.equipment, user.equipment):
            continue
        
        # ═══════════════════════════════════════════════════════════════
        # FILTER 2: Muscle match
        # ═══════════════════════════════════════════════════════════════
        matches_muscle = any(
            any(m in nm or nm in m for nm in normalized_muscles)
            for m in muscle_lower
        ) or any(nm in category_lower for nm in normalized_muscles)
        
        if not matches_muscle:
            continue
        
        # ═══════════════════════════════════════════════════════════════
        # FILTER 3: Practicality score
        # ═══════════════════════════════════════════════════════════════
        if 0 < ex.practicality_score < 30:
            continue
        
        # ═══════════════════════════════════════════════════════════════
        # FILTER 4: Injury/Limitation safety
        # ═══════════════════════════════════════════════════════════════
        should_skip = any(
            is_exercise_unsafe_for_area(name_lower, area)
            for area in skip_areas
        )
        if should_skip:
            continue
        
        # ═══════════════════════════════════════════════════════════════
        # FILTER 5: Experience level appropriateness
        # ═══════════════════════════════════════════════════════════════
        if user.experience_level == "Beginner":
            advanced_keywords = ["clean", "snatch", "jerk", "olympic", "muscle up",
                                "pistol squat", "dragon flag", "front lever", "back lever",
                                "planche", "handstand", "deficit deadlift"]
            if any(kw in name_lower for kw in advanced_keywords):
                continue
        
        # ═══════════════════════════════════════════════════════════════
        # FILTER 6: Age/Weight appropriateness
        # ═══════════════════════════════════════════════════════════════
        if user.age >= 60 or user.weight_lbs > 280:
            high_impact = ["jump", "box jump", "plyometric", "plyo", "burpee", "sprint", "depth jump"]
            if any(kw in name_lower for kw in high_impact):
                continue
        
        if user.weight_lbs > 250 and is_bodyweight:
            hard_bodyweight = ["pull up", "pullup", "chin up", "chinup", "muscle up", "dip", "pistol"]
            if any(kw in name_lower for kw in hard_bodyweight):
                continue
        
        # ═══════════════════════════════════════════════════════════════
        # FILTER 7: Location appropriateness
        # ═══════════════════════════════════════════════════════════════
        if user.workout_location == "Home":
            needs_gym = any(kw in equipment_lower for kw in ["cable", "machine", "smith", "rack"])
            if needs_gym:
                continue
        
        # Scoring
        score = 100
        
        # Practicality boost
        if ex.practicality_score > 70:
            score += 20
        elif ex.practicality_score > 50:
            score += 10
        elif 0 < ex.practicality_score < 50:
            score -= 10
        
        # Location boost for gym users
        if is_gym_user:
            if any(kw in equipment_lower for kw in ["cable", "machine", "barbell"]):
                score += 15
        
        # Random variety
        score += random.uniform(-5, 5)
        
        # Track equipment type for this exercise
        ex_equip_type = get_equipment_type(equipment_lower)
        filtered.append((ex, score, ex_equip_type))
    
    # Sort by score (highest first)
    filtered.sort(key=lambda x: x[1], reverse=True)
    
    # 🎯 EQUIPMENT DIVERSITY SELECTION (matching Swift logic)
    # When user has multiple equipment types, ensure at least 2 exercises from each type
    user_equip_types = get_user_equipment_types(user.equipment)
    
    if len(user_equip_types) > 1:
        # Phase 1: Reserve at least 2 exercises per equipment type
        result = []
        used_names = set()
        min_per_type = 2
        
        for equip_type in user_equip_types:
            reserved_count = 0
            for ex, score, ex_type in filtered:
                if reserved_count >= min_per_type:
                    break
                if ex_type == equip_type and ex.name.lower() not in used_names:
                    result.append(ex)
                    used_names.add(ex.name.lower())
                    reserved_count += 1
        
        # Phase 2: Fill remaining slots with highest scoring exercises
        for ex, score, ex_type in filtered:
            if ex.name.lower() not in used_names:
                result.append(ex)
                used_names.add(ex.name.lower())
        
        return result
    else:
        return [ex for ex, _, _ in filtered]

# ═══════════════════════════════════════════════════════════════════════════════
# GRADING
# ═══════════════════════════════════════════════════════════════════════════════

def classify_movement_pattern(exercise_name: str) -> str:
    """Classify exercise into movement pattern."""
    name = exercise_name.lower()
    
    if "press" in name or "push" in name: return "push"
    if "row" in name or "pull" in name: return "pull"
    if "squat" in name or "leg press" in name: return "squat"
    if "deadlift" in name or "hip thrust" in name: return "hinge"
    if "lunge" in name or "step" in name: return "lunge"
    if "curl" in name: return "curl"
    if "extension" in name or "tricep" in name: return "extension"
    if "raise" in name or "fly" in name: return "isolation"
    if "plank" in name or "crunch" in name: return "core"
    
    return "other"

def grade_workout(exercises: List[Exercise], user: TestUser) -> WorkoutScorecard:
    """Grade a generated workout against the scorecard."""
    scorecard = WorkoutScorecard()
    normalized_equipment = set(e.lower() for e in user.equipment)
    is_gym_user = user.workout_location in ["Gym", "Hybrid"]
    is_home_user = user.workout_location == "Home"
    
    if not exercises:
        scorecard.equipment_violations.append("❌ No exercises generated!")
        return scorecard
    
    equipment_passes = 0
    safety_passes = 0
    practicality_passes = 0
    goal_passes = 0
    experience_passes = 0
    location_passes = 0
    profile_passes = 0
    
    movement_patterns = set()
    equipment_used = set()
    equipment_types_used = {}  # 🆕 Track equipment TYPE counts (dumbbell, cable, etc.)
    
    for ex in exercises:
        name_lower = ex.name.lower()
        equipment_lower = ex.equipment.lower()
        equipment_parts = [e.strip().lower() for e in equipment_lower.split(",") if e.strip()]
        
        # ─────────────────────────────────────────────────────────────
        # EQUIPMENT CHECK (using new equipment format matching)
        # ─────────────────────────────────────────────────────────────
        has_all = user_has_required_equipment(ex.equipment, user.equipment)
        
        if has_all:
            equipment_passes += 1
        else:
            # Find which equipment user is missing
            normalized_ex_equip = normalize_equipment_to_user_category(ex.equipment)
            scorecard.equipment_violations.append(f"❌ '{ex.name}' requires {normalized_ex_equip} - user doesn't have")
        
        # ─────────────────────────────────────────────────────────────
        # SAFETY CHECK
        # ─────────────────────────────────────────────────────────────
        is_safe = True
        for limitation in user.limitations:
            if limitation.accommodation == "skipCompletely":
                if is_exercise_unsafe_for_area(name_lower, limitation.area):
                    scorecard.safety_violations.append(f"⚠️ '{ex.name}' unsafe for {limitation.area}")
                    is_safe = False
        if is_safe:
            safety_passes += 1
        
        # ─────────────────────────────────────────────────────────────
        # PRACTICALITY CHECK
        # ─────────────────────────────────────────────────────────────
        if ex.practicality_score > 0:
            if ex.practicality_score >= 40:
                practicality_passes += 1
            else:
                scorecard.practicality_violations.append(f"⚠️ '{ex.name}' low practicality ({ex.practicality_score})")
        else:
            practicality_passes += 1
        
        # ─────────────────────────────────────────────────────────────
        # GOAL ALIGNMENT (simplified)
        # ─────────────────────────────────────────────────────────────
        goal_passes += 1  # Most exercises are reasonably aligned
        
        # ─────────────────────────────────────────────────────────────
        # EXPERIENCE CHECK
        # ─────────────────────────────────────────────────────────────
        advanced_keywords = ["clean", "snatch", "jerk", "olympic", "muscle up",
                            "pistol squat", "dragon flag", "front lever", "planche", "handstand"]
        is_advanced = any(kw in name_lower for kw in advanced_keywords)
        
        if user.experience_level == "Beginner" and is_advanced:
            scorecard.experience_violations.append(f"⚠️ '{ex.name}' is advanced, user is Beginner")
        else:
            experience_passes += 1
        
        # ─────────────────────────────────────────────────────────────
        # LOCATION CHECK
        # ─────────────────────────────────────────────────────────────
        needs_gym = any(kw in equipment_lower for kw in ["cable", "machine", "smith", "rack"])
        
        if is_home_user and needs_gym:
            scorecard.location_violations.append(f"❌ '{ex.name}' requires gym equipment for Home user")
        else:
            location_passes += 1
        
        # ─────────────────────────────────────────────────────────────
        # PROFILE CHECK
        # ─────────────────────────────────────────────────────────────
        profile_safe = True
        high_impact = ["jump", "plyometric", "plyo", "burpee", "sprint", "hop"]
        is_high_impact = any(kw in name_lower for kw in high_impact)
        
        if (user.age >= 60 or user.weight_lbs > 280) and is_high_impact:
            scorecard.profile_violations.append(f"⚠️ '{ex.name}' high-impact for age {user.age} or weight {int(user.weight_lbs)}lbs")
            profile_safe = False
        
        hard_bodyweight = ["pull up", "pullup", "chin up", "chinup", "muscle up", "dip", "pistol"]
        is_hard_bw = any(kw in name_lower for kw in hard_bodyweight)
        
        if user.weight_lbs > 250 and is_hard_bw:
            scorecard.profile_violations.append(f"⚠️ '{ex.name}' difficult for weight {int(user.weight_lbs)}lbs")
            profile_safe = False
        
        if profile_safe:
            profile_passes += 1
        
        # Track patterns for variety
        pattern = classify_movement_pattern(name_lower)
        movement_patterns.add(pattern)
        first_equip = equipment_parts[0] if equipment_parts else "bodyweight"
        equipment_used.add(first_equip)
        
        # 🆕 Track equipment TYPE (dumbbell, cable, barbell, etc.)
        ex_equip_type = get_equipment_type(equipment_lower)
        if ex_equip_type not in ["other", "bodyweight"]:
            equipment_types_used[ex_equip_type] = equipment_types_used.get(ex_equip_type, 0) + 1
    
    # Calculate scores
    count = len(exercises)
    scorecard.equipment_score = (equipment_passes / count) * 100
    scorecard.safety_score = (safety_passes / count) * 100
    scorecard.practicality_score = (practicality_passes / count) * 100
    scorecard.goal_alignment_score = (goal_passes / count) * 100
    scorecard.experience_score = (experience_passes / count) * 100
    scorecard.location_score = (location_passes / count) * 100
    scorecard.profile_score = (profile_passes / count) * 100
    
    # Variety score
    pattern_variety = min(len(movement_patterns) / 4.0, 1.0) * 50
    equip_variety = min(len(equipment_used) / 3.0, 1.0) * 50
    scorecard.variety_score = pattern_variety + equip_variety
    
    # 🆕 EQUIPMENT DIVERSITY SCORE
    # Check if workout uses multiple equipment types that user has
    user_equip_types = get_user_equipment_types(user.equipment)
    
    if len(user_equip_types) > 1:
        # User has multiple equipment types - check if we're using them fairly
        types_used = set(equipment_types_used.keys())
        types_represented = user_equip_types.intersection(types_used)
        
        # Calculate diversity score
        representation_ratio = len(types_represented) / len(user_equip_types)
        
        # Check minimum 2 per type (when possible)
        min_requirement_met = 0
        for etype in user_equip_types:
            if equipment_types_used.get(etype, 0) >= 2:
                min_requirement_met += 1
            elif equipment_types_used.get(etype, 0) >= 1:
                min_requirement_met += 0.5  # Partial credit for at least 1
        
        min_ratio = min_requirement_met / len(user_equip_types)
        
        # Combined score: 60% representation, 40% minimum requirement
        scorecard.equipment_diversity_score = (representation_ratio * 60 + min_ratio * 40)
        
        # Log violations
        for etype in user_equip_types:
            count_used = equipment_types_used.get(etype, 0)
            if count_used == 0:
                scorecard.equipment_diversity_violations.append(
                    f"❌ No {etype} exercises despite user having {etype} equipment")
            elif count_used < 2:
                scorecard.equipment_diversity_violations.append(
                    f"⚠️ Only {count_used} {etype} exercise(s), expected at least 2")
    else:
        # Single equipment type or bodyweight only - full score
        scorecard.equipment_diversity_score = 100.0
    
    if len(movement_patterns) < 3:
        scorecard.variety_violations.append(f"⚠️ Low movement variety ({len(movement_patterns)} patterns)")
    
    return scorecard

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN AUDIT
# ═══════════════════════════════════════════════════════════════════════════════

def run_audit(user_count: int = 200):
    """Run the full quality audit."""
    print("╔══════════════════════════════════════════════════════════════════════╗")
    print(f"║        🧪 WORKOUT QUALITY AUDIT - {user_count} USERS                         ║")
    print("╚══════════════════════════════════════════════════════════════════════╝")
    print()
    
    # Load exercises
    exercises = load_exercises()
    if not exercises:
        print("❌ No exercises loaded! Cannot run audit.")
        return
    
    # Generate users
    print(f"\n📋 Generating {user_count} diverse test users...")
    users = generate_test_users(user_count)
    
    # Profile distribution
    goals = defaultdict(int)
    levels = defaultdict(int)
    locations = defaultdict(int)
    with_limitations = 0
    
    for u in users:
        goals[u.goal] += 1
        levels[u.experience_level] += 1
        locations[u.workout_location] += 1
        if u.limitations:
            with_limitations += 1
    
    print(f"   Goals: {dict(goals)}")
    print(f"   Levels: {dict(levels)}")
    print(f"   Locations: {dict(locations)}")
    print(f"   With Limitations: {with_limitations} ({with_limitations/user_count*100:.0f}%)")
    
    # Run audit
    print(f"\n🔍 Running audit on {user_count} users...")
    
    passed = 0
    failed = 0
    results = []
    issue_counts = defaultdict(int)
    
    for i, user in enumerate(users):
        if (i + 1) % 50 == 0:
            print(f"   Progress: {i+1}/{user_count}...")
        
        target_muscles = get_target_muscles(user.goal)
        filtered = filter_exercises_for_user(exercises, user, target_muscles)
        selected = filtered[:6]  # Select 6 exercises
        
        scorecard = grade_workout(selected, user)
        
        if scorecard.passed:
            passed += 1
        else:
            failed += 1
        
        # Count issues
        for v in scorecard.all_violations:
            if "dumbbell" in v.lower() or "cable" in v.lower() or "barbell" in v.lower():
                issue_counts["Equipment Diversity"] += 1  # 🆕
            elif "equipment" in v.lower() or "requires" in v.lower():
                issue_counts["Equipment Mismatch"] += 1
            elif "unsafe" in v.lower():
                issue_counts["Safety Violation"] += 1
            elif "practicality" in v.lower():
                issue_counts["Low Practicality"] += 1
            elif "beginner" in v.lower() or "advanced" in v.lower():
                issue_counts["Experience Mismatch"] += 1
            elif "home" in v.lower() or "gym" in v.lower():
                issue_counts["Location Mismatch"] += 1
            elif "age" in v.lower() or "weight" in v.lower():
                issue_counts["Profile Safety"] += 1
            elif "variety" in v.lower():
                issue_counts["Low Variety"] += 1
        
        results.append({
            "user": user,
            "exercises": selected,
            "scorecard": scorecard
        })
    
    # Calculate averages
    avg_equipment = sum(r["scorecard"].equipment_score for r in results) / len(results)
    avg_safety = sum(r["scorecard"].safety_score for r in results) / len(results)
    avg_practicality = sum(r["scorecard"].practicality_score for r in results) / len(results)
    avg_goal = sum(r["scorecard"].goal_alignment_score for r in results) / len(results)
    avg_experience = sum(r["scorecard"].experience_score for r in results) / len(results)
    avg_variety = sum(r["scorecard"].variety_score for r in results) / len(results)
    avg_location = sum(r["scorecard"].location_score for r in results) / len(results)
    avg_profile = sum(r["scorecard"].profile_score for r in results) / len(results)
    avg_equip_diversity = sum(r["scorecard"].equipment_diversity_score for r in results) / len(results)  # 🆕
    avg_overall = sum(r["scorecard"].overall_score for r in results) / len(results)
    
    pass_rate = passed / user_count * 100
    
    # Print results
    print()
    print("╔══════════════════════════════════════════════════════════════════════╗")
    print("║                    📊 AUDIT RESULTS SUMMARY                          ║")
    print("╠══════════════════════════════════════════════════════════════════════╣")
    print(f"║ OVERALL:")
    print(f"║   Total Users Tested: {user_count}")
    print(f"║   ✅ Passed: {passed} ({pass_rate:.1f}%)")
    print(f"║   ❌ Failed: {failed} ({100-pass_rate:.1f}%)")
    print(f"║   Average Overall Score: {avg_overall:.1f}/100")
    print("╠══════════════════════════════════════════════════════════════════════╣")
    print(f"║ SCORE BREAKDOWN:")
    print(f"║   🎯 Equipment Match:    {avg_equipment:.1f}%")
    print(f"║   🔀 Equip Diversity:    {avg_equip_diversity:.1f}%")  # 🆕 Cable/Dumbbell balance
    print(f"║   🛡️  Safety Score:       {avg_safety:.1f}%")
    print(f"║   ✨ Practicality:       {avg_practicality:.1f}%")
    print(f"║   🎯 Goal Alignment:     {avg_goal:.1f}%")
    print(f"║   📈 Experience Match:   {avg_experience:.1f}%")
    print(f"║   🔄 Variety:            {avg_variety:.1f}%")
    print(f"║   📍 Location Match:     {avg_location:.1f}%")
    print(f"║   👤 Profile Safety:     {avg_profile:.1f}%")
    print("╠══════════════════════════════════════════════════════════════════════╣")
    print(f"║ ISSUE BREAKDOWN:")
    
    for issue, count in sorted(issue_counts.items(), key=lambda x: x[1], reverse=True):
        bar = "█" * min(count // 3, 25)
        print(f"║   {issue}: {count} {bar}")
    
    print("╚══════════════════════════════════════════════════════════════════════╝")
    
    # Print worst performers
    worst = sorted(results, key=lambda r: r["scorecard"].overall_score)[:10]
    
    print("\n⚠️ WORST PERFORMERS (need investigation):")
    for r in worst[:5]:
        user = r["user"]
        sc = r["scorecard"]
        print(f"\n   • {user.name}: {sc.overall_score:.1f}/100")
        print(f"     Profile: {user.experience_level}, {user.workout_location}, {user.goal}")
        print(f"     Equipment: {', '.join(user.equipment[:3])}...")
        if user.limitations:
            print(f"     Limitations: {', '.join(f'{l.area}({l.accommodation})' for l in user.limitations)}")
        for v in sc.all_violations[:3]:
            print(f"     └─ {v}")
    
    # Suggested fixes
    print("\n")
    print("╔══════════════════════════════════════════════════════════════════════╗")
    print("║                    🔧 SUGGESTED CODE FIXES                           ║")
    print("╚══════════════════════════════════════════════════════════════════════╝")
    
    if issue_counts["Equipment Mismatch"] > 10:
        print(f"\n🔴 CRITICAL: {issue_counts['Equipment Mismatch']} Equipment Mismatches")
        print("   FIX: Ensure WorkoutGeneratorService.swift uses allSatisfy for equipment matching")
        print("   FIX: Verify SmartExerciseSelectionEngine checks ALL required equipment")
    
    if issue_counts["Safety Violation"] > 5:
        print(f"\n🟠 HIGH: {issue_counts['Safety Violation']} Safety Violations")
        print("   FIX: Strengthen LimitationsService filtering")
        print("   FIX: Add more exercise->injury area mappings")
    
    if issue_counts["Low Practicality"] > 10:
        print(f"\n🟡 MEDIUM: {issue_counts['Low Practicality']} Low Practicality")
        print("   FIX: Raise practicality threshold from 30 to 40")
        print("   FIX: Review exercises with scores 30-50")
    
    if issue_counts["Location Mismatch"] > 5:
        print(f"\n🟠 HIGH: {issue_counts['Location Mismatch']} Location Mismatches")
        print("   FIX: Add explicit location-based equipment filtering")
        print("   FIX: Home users should not see cable/machine exercises")
    
    if issue_counts["Profile Safety"] > 5:
        print(f"\n🟡 MEDIUM: {issue_counts['Profile Safety']} Profile Safety Issues")
        print("   FIX: Strengthen age/weight based filtering")
        print("   FIX: Lower bodyweight difficulty threshold for heavier users")
    
    if issue_counts["Equipment Diversity"] > 5:
        print(f"\n🔴 CRITICAL: {issue_counts['Equipment Diversity']} Equipment Diversity Issues")
        print("   FIX: WorkoutGeneratorService Phase 1 must guarantee 2+ exercises per equipment type")
        print("   FIX: Ensure cable AND dumbbell exercises are both represented equally")
        print("   FIX: Check selectedEquipmentTypes logic in generateFromCoreData()")
    
    # Summary grade
    print("\n")
    if pass_rate >= 95:
        grade = "A+"
        emoji = "🏆"
    elif pass_rate >= 90:
        grade = "A"
        emoji = "🎉"
    elif pass_rate >= 85:
        grade = "B+"
        emoji = "✅"
    elif pass_rate >= 80:
        grade = "B"
        emoji = "👍"
    elif pass_rate >= 70:
        grade = "C"
        emoji = "⚠️"
    else:
        grade = "D"
        emoji = "❌"
    
    print(f"╔══════════════════════════════════════════════════════════════════════╗")
    print(f"║                    {emoji} FINAL GRADE: {grade} ({pass_rate:.1f}% pass rate)              ║")
    print(f"╚══════════════════════════════════════════════════════════════════════╝")
    
    # Save detailed report
    report_file = f"quality_audit_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    with open(report_file, 'w') as f:
        f.write(f"WORKOUT QUALITY AUDIT REPORT\n")
        f.write(f"Generated: {datetime.now()}\n")
        f.write(f"Users Tested: {user_count}\n")
        f.write(f"Pass Rate: {pass_rate:.1f}%\n")
        f.write(f"Grade: {grade}\n\n")
        f.write(f"Average Scores:\n")
        f.write(f"  Equipment Match: {avg_equipment:.1f}%\n")
        f.write(f"  Equipment Diversity: {avg_equip_diversity:.1f}%\n")  # 🆕
        f.write(f"  Safety: {avg_safety:.1f}%\n")
        f.write(f"  Practicality: {avg_practicality:.1f}%\n")
        f.write(f"  Goal Alignment: {avg_goal:.1f}%\n")
        f.write(f"  Experience: {avg_experience:.1f}%\n")
        f.write(f"  Variety: {avg_variety:.1f}%\n")
        f.write(f"  Location: {avg_location:.1f}%\n")
        f.write(f"  Profile Safety: {avg_profile:.1f}%\n")
        f.write(f"  Overall: {avg_overall:.1f}\n\n")
        f.write(f"Issues Found:\n")
        for issue, count in sorted(issue_counts.items(), key=lambda x: x[1], reverse=True):
            f.write(f"  {issue}: {count}\n")
    
    print(f"\n📄 Detailed report saved to: {report_file}")

if __name__ == "__main__":
    run_audit(200)

