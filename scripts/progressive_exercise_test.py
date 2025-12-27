#!/usr/bin/env python3
"""
Progressive Exercise System Test Suite
======================================
Simulates 14 diverse test users going through 6 workout days each.
Tests the progressive unlock system and foundational exercise prioritization.
Generates a comprehensive HTML report with scoring.
"""

import json
import random
from datetime import datetime
from dataclasses import dataclass, field
from typing import List, Dict, Set, Optional
from enum import Enum

# =============================================================================
# FOUNDATIONAL EXERCISE DATABASE (Mirror of Swift implementation)
# =============================================================================

class FoundationTier(Enum):
    ESSENTIAL = 1      # Must-know exercises (show first 1-3 workouts)
    FUNDAMENTAL = 2    # Core exercises (show after 3-5 workouts)
    STANDARD = 3       # Common exercises (show after 5-10 workouts)
    VARIETY = 4        # Good variety exercises (show after 10+ workouts)
    NON_FOUNDATIONAL = 5  # Not in foundational database

# Foundational exercises by equipment and muscle group
FOUNDATIONAL_EXERCISES = {
    # BARBELL
    "barbell": {
        "chest": [
            {"name": "Barbell Bench Press", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Barbell Incline Bench Press", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Close Grip Barbell Bench Press", "tier": FoundationTier.STANDARD, "compound": True},
        ],
        "back": [
            {"name": "Barbell Bent Over Row", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Barbell Deadlift", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Barbell Shrug", "tier": FoundationTier.STANDARD, "compound": False},
        ],
        "shoulders": [
            {"name": "Barbell Overhead Press", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Barbell Upright Row", "tier": FoundationTier.VARIETY, "compound": True},
        ],
        "legs": [
            {"name": "Barbell Squat", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Barbell Romanian Deadlift", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Barbell Front Squat", "tier": FoundationTier.STANDARD, "compound": True},
            {"name": "Barbell Lunge", "tier": FoundationTier.VARIETY, "compound": True},
            {"name": "Barbell Hip Thrust", "tier": FoundationTier.STANDARD, "compound": True},
        ],
        "biceps": [
            {"name": "Barbell Curl", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
        ],
        "triceps": [
            {"name": "Barbell Skull Crusher", "tier": FoundationTier.VARIETY, "compound": False},
        ],
    },
    # DUMBBELLS
    "dumbbells": {
        "chest": [
            {"name": "Dumbbell Bench Press", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Dumbbell Fly", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Dumbbell Incline Press", "tier": FoundationTier.STANDARD, "compound": True},
            {"name": "Dumbbell Pullover", "tier": FoundationTier.VARIETY, "compound": False},
        ],
        "back": [
            {"name": "Dumbbell Row", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Dumbbell Shrug", "tier": FoundationTier.STANDARD, "compound": False},
        ],
        "shoulders": [
            {"name": "Dumbbell Shoulder Press", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Dumbbell Lateral Raise", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Dumbbell Front Raise", "tier": FoundationTier.STANDARD, "compound": False},
            {"name": "Dumbbell Rear Delt Fly", "tier": FoundationTier.STANDARD, "compound": False},
            {"name": "Arnold Press", "tier": FoundationTier.VARIETY, "compound": True},
        ],
        "legs": [
            {"name": "Dumbbell Goblet Squat", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Dumbbell Lunge", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Dumbbell Romanian Deadlift", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Dumbbell Calf Raise", "tier": FoundationTier.VARIETY, "compound": False},
        ],
        "biceps": [
            {"name": "Dumbbell Bicep Curl", "tier": FoundationTier.ESSENTIAL, "compound": False},
            {"name": "Dumbbell Hammer Curl", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Dumbbell Concentration Curl", "tier": FoundationTier.VARIETY, "compound": False},
        ],
        "triceps": [
            {"name": "Dumbbell Tricep Extension", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Dumbbell Tricep Kickback", "tier": FoundationTier.VARIETY, "compound": False},
        ],
    },
    # CABLES
    "cables": {
        "chest": [
            {"name": "Cable Fly", "tier": FoundationTier.ESSENTIAL, "compound": False},
            {"name": "Cable Chest Press", "tier": FoundationTier.STANDARD, "compound": True},
        ],
        "back": [
            {"name": "Seated Cable Row", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Lat Pulldown", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Straight Arm Pulldown", "tier": FoundationTier.VARIETY, "compound": False},
        ],
        "shoulders": [
            {"name": "Cable Lateral Raise", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Cable Face Pull", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Cable Upright Row", "tier": FoundationTier.VARIETY, "compound": True},
        ],
        "biceps": [
            {"name": "Cable Bicep Curl", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
        ],
        "triceps": [
            {"name": "Cable Tricep Pushdown", "tier": FoundationTier.ESSENTIAL, "compound": False},
            {"name": "Cable Overhead Tricep Extension", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
        ],
        "core": [
            {"name": "Cable Woodchop", "tier": FoundationTier.STANDARD, "compound": True},
            {"name": "Cable Crunch", "tier": FoundationTier.VARIETY, "compound": False},
        ],
        "glutes": [
            {"name": "Cable Glute Kickback", "tier": FoundationTier.STANDARD, "compound": False},
            {"name": "Cable Pull Through", "tier": FoundationTier.VARIETY, "compound": True},
        ],
    },
    # MACHINES
    "machines": {
        "chest": [
            {"name": "Machine Chest Press", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Pec Deck", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
        ],
        "back": [
            {"name": "Machine Row", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Machine Rear Delt Fly", "tier": FoundationTier.VARIETY, "compound": False},
        ],
        "shoulders": [
            {"name": "Machine Shoulder Press", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Machine Lateral Raise", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
        ],
        "legs": [
            {"name": "Leg Press", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Leg Curl", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Leg Extension", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Hack Squat", "tier": FoundationTier.STANDARD, "compound": True},
            {"name": "Hip Abduction Machine", "tier": FoundationTier.STANDARD, "compound": False},
            {"name": "Hip Adduction Machine", "tier": FoundationTier.STANDARD, "compound": False},
            {"name": "Machine Calf Raise", "tier": FoundationTier.STANDARD, "compound": False},
            {"name": "Glute Machine", "tier": FoundationTier.VARIETY, "compound": False},
        ],
        "biceps": [
            {"name": "Machine Preacher Curl", "tier": FoundationTier.VARIETY, "compound": False},
        ],
    },
    # BODYWEIGHT
    "bodyweight": {
        "chest": [
            {"name": "Push Up", "tier": FoundationTier.ESSENTIAL, "compound": True},
        ],
        "back": [
            {"name": "Pull Up", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Chin Up", "tier": FoundationTier.STANDARD, "compound": True},
            {"name": "Superman", "tier": FoundationTier.STANDARD, "compound": False},
        ],
        "shoulders": [],
        "legs": [
            {"name": "Bodyweight Squat", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Bodyweight Lunge", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Glute Bridge", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Step Up", "tier": FoundationTier.VARIETY, "compound": True},
        ],
        "triceps": [
            {"name": "Dip", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
        ],
        "core": [
            {"name": "Plank", "tier": FoundationTier.ESSENTIAL, "compound": False},
            {"name": "Crunch", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
            {"name": "Mountain Climber", "tier": FoundationTier.STANDARD, "compound": True},
            {"name": "Lying Leg Raise", "tier": FoundationTier.STANDARD, "compound": False},
            {"name": "Side Plank", "tier": FoundationTier.VARIETY, "compound": False},
        ],
        "full_body": [
            {"name": "Burpee", "tier": FoundationTier.VARIETY, "compound": True},
        ],
    },
    # KETTLEBELL
    "kettlebell": {
        "glutes": [
            {"name": "Kettlebell Swing", "tier": FoundationTier.ESSENTIAL, "compound": True},
        ],
        "legs": [
            {"name": "Kettlebell Goblet Squat", "tier": FoundationTier.ESSENTIAL, "compound": True},
            {"name": "Kettlebell Deadlift", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Kettlebell Sumo Squat", "tier": FoundationTier.STANDARD, "compound": True},
            {"name": "Kettlebell Lunge", "tier": FoundationTier.STANDARD, "compound": True},
        ],
        "shoulders": [
            {"name": "Kettlebell Press", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
        ],
        "back": [
            {"name": "Kettlebell Row", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
        ],
        "full_body": [
            {"name": "Turkish Get Up", "tier": FoundationTier.VARIETY, "compound": True},
            {"name": "Kettlebell Clean", "tier": FoundationTier.VARIETY, "compound": True},
        ],
        "core": [
            {"name": "Kettlebell Windmill", "tier": FoundationTier.VARIETY, "compound": True},
        ],
    },
    # RESISTANCE BANDS
    "bands": {
        "chest": [
            {"name": "Band Chest Press", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Band Fly", "tier": FoundationTier.STANDARD, "compound": False},
        ],
        "back": [
            {"name": "Band Row", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Band Pull Apart", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
        ],
        "shoulders": [
            {"name": "Band Shoulder Press", "tier": FoundationTier.STANDARD, "compound": True},
            {"name": "Band Lateral Raise", "tier": FoundationTier.STANDARD, "compound": False},
        ],
        "legs": [
            {"name": "Band Squat", "tier": FoundationTier.FUNDAMENTAL, "compound": True},
            {"name": "Band Glute Bridge", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
        ],
        "biceps": [
            {"name": "Band Bicep Curl", "tier": FoundationTier.FUNDAMENTAL, "compound": False},
        ],
        "triceps": [
            {"name": "Band Tricep Extension", "tier": FoundationTier.STANDARD, "compound": False},
        ],
    },
}

# Non-foundational (obscure) exercises that should NOT appear for beginners
OBSCURE_EXERCISES = {
    "chest": [
        "Behind the Neck Cable Fly",
        "Svend Press",
        "Guillotine Press",
        "Single Arm Rotating Cable Fly",
        "Decline Twisting Dumbbell Press",
    ],
    "back": [
        "Meadows Row",
        "Pendlay Row with Pause",
        "Single Arm Reverse Grip Pulldown",
        "Bayesian Cable Row",
    ],
    "shoulders": [
        "Bradford Press",
        "Cuban Press",
        "Waiter Carry Overhead Press",
        "Behind the Neck Press",
    ],
    "triceps": [
        "Behind the Back Cable Tricep Extension",
        "JM Press",
        "Tate Press",
        "Rolling Dumbbell Tricep Extension",
    ],
    "biceps": [
        "Zottman Curl",
        "Spider Curl (Prone Incline)",
        "Bayesian Cable Curl",
        "Drag Curl",
    ],
    "legs": [
        "Jefferson Deadlift",
        "Zercher Squat",
        "Sissy Squat",
        "Single Leg Deficit Deadlift",
    ],
}

# Exercise contraindications for injuries
INJURY_CONTRAINDICATIONS = {
    "lower_back": [
        "Deadlift", "Barbell Row", "Good Morning", "Bent Over", 
        "Romanian Deadlift", "Back Extension", "Squat"
    ],
    "shoulder": [
        "Overhead Press", "Behind the Neck", "Upright Row", 
        "Lateral Raise", "Arnold Press", "Dip"
    ],
    "knee": [
        "Squat", "Lunge", "Leg Press", "Leg Extension", 
        "Step Up", "Jump", "Plyometric"
    ],
    "wrist": [
        "Push Up", "Bench Press", "Curl", "Overhead Press",
        "Front Squat", "Clean"
    ],
    "neck": [
        "Shrug", "Behind the Neck", "Upright Row"
    ],
}


# =============================================================================
# TEST USER PROFILES
# =============================================================================

@dataclass
class TestUser:
    id: int
    name: str
    age: int
    gender: str
    experience_level: str  # beginner, intermediate, advanced
    fitness_goal: str
    workout_environment: str  # gym, home, outdoor
    equipment: List[str]
    injuries: List[str]
    weight_lbs: int
    special_situation: str
    
    # Tracking
    workouts_completed: int = 0
    exercises_done: Set[str] = field(default_factory=set)
    favorites: Set[str] = field(default_factory=set)
    swapped_exercises: Dict[str, int] = field(default_factory=dict)


# Create 14 diverse test users
TEST_USERS = [
    TestUser(
        id=1,
        name="Sarah",
        age=28,
        gender="female",
        experience_level="beginner",
        fitness_goal="lose weight",
        workout_environment="gym",
        equipment=["dumbbells", "cables", "machines"],
        injuries=[],
        weight_lbs=165,
        special_situation="First time in a gym, intimidated by free weights"
    ),
    TestUser(
        id=2,
        name="Mike",
        age=35,
        gender="male",
        experience_level="beginner",
        fitness_goal="build muscle",
        workout_environment="gym",
        equipment=["barbell", "dumbbells", "cables", "machines"],
        injuries=["lower_back"],
        weight_lbs=195,
        special_situation="Office worker with herniated disc, doctor cleared for exercise"
    ),
    TestUser(
        id=3,
        name="Jennifer",
        age=45,
        gender="female",
        experience_level="intermediate",
        fitness_goal="get stronger",
        workout_environment="home",
        equipment=["dumbbells", "bands", "bodyweight"],
        injuries=[],
        weight_lbs=140,
        special_situation="Busy mom, works out during kids' nap time"
    ),
    TestUser(
        id=4,
        name="David",
        age=22,
        gender="male",
        experience_level="beginner",
        fitness_goal="build muscle",
        workout_environment="gym",
        equipment=["barbell", "dumbbells", "cables", "machines"],
        injuries=[],
        weight_lbs=155,
        special_situation="College student, wants to get bigger"
    ),
    TestUser(
        id=5,
        name="Maria",
        age=52,
        gender="female",
        experience_level="beginner",
        fitness_goal="general fitness",
        workout_environment="gym",
        equipment=["machines", "cables"],
        injuries=["knee"],
        weight_lbs=170,
        special_situation="Post-menopause, has knee arthritis"
    ),
    TestUser(
        id=6,
        name="James",
        age=65,
        gender="male",
        experience_level="beginner",
        fitness_goal="stay healthy",
        workout_environment="gym",
        equipment=["machines", "cables", "dumbbells"],
        injuries=["shoulder"],
        weight_lbs=185,
        special_situation="Retired, rotator cuff surgery 6 months ago"
    ),
    TestUser(
        id=7,
        name="Ashley",
        age=30,
        gender="female",
        experience_level="advanced",
        fitness_goal="build muscle",
        workout_environment="gym",
        equipment=["barbell", "dumbbells", "cables", "machines", "kettlebell"],
        injuries=[],
        weight_lbs=135,
        special_situation="Competitive powerlifter, wants variety in accessories"
    ),
    TestUser(
        id=8,
        name="Robert",
        age=40,
        gender="male",
        experience_level="intermediate",
        fitness_goal="lose weight",
        workout_environment="home",
        equipment=["bodyweight", "bands", "kettlebell"],
        injuries=[],
        weight_lbs=220,
        special_situation="Works from home, no gym membership"
    ),
    TestUser(
        id=9,
        name="Emily",
        age=25,
        gender="female",
        experience_level="beginner",
        fitness_goal="tone & define",
        workout_environment="gym",
        equipment=["dumbbells", "cables", "machines"],
        injuries=["wrist"],
        weight_lbs=125,
        special_situation="Carpal tunnel syndrome, avoids heavy gripping"
    ),
    TestUser(
        id=10,
        name="Marcus",
        age=55,
        gender="male",
        experience_level="beginner",
        fitness_goal="get stronger",
        workout_environment="gym",
        equipment=["barbell", "dumbbells", "machines"],
        injuries=["lower_back", "knee"],
        weight_lbs=290,
        special_situation="Heavy user, multiple joint issues, needs safe exercises"
    ),
    TestUser(
        id=11,
        name="Lisa",
        age=33,
        gender="female",
        experience_level="intermediate",
        fitness_goal="build muscle",
        workout_environment="gym",
        equipment=["barbell", "dumbbells", "cables"],
        injuries=[],
        weight_lbs=145,
        special_situation="Returning after 2-year break from pregnancy"
    ),
    TestUser(
        id=12,
        name="Kevin",
        age=19,
        gender="male",
        experience_level="beginner",
        fitness_goal="build muscle",
        workout_environment="home",
        equipment=["dumbbells", "bodyweight"],
        injuries=[],
        weight_lbs=145,
        special_situation="Teen with basic home gym setup, limited equipment"
    ),
    TestUser(
        id=13,
        name="Patricia",
        age=48,
        gender="female",
        experience_level="beginner",
        fitness_goal="lose weight",
        workout_environment="gym",
        equipment=["machines", "cables", "bodyweight"],
        injuries=["neck"],
        weight_lbs=195,
        special_situation="Chronic neck pain, avoids overhead movements"
    ),
    TestUser(
        id=14,
        name="Thomas",
        age=27,
        gender="male",
        experience_level="advanced",
        fitness_goal="endurance",
        workout_environment="outdoor",
        equipment=["bodyweight", "kettlebell"],
        injuries=[],
        weight_lbs=175,
        special_situation="Trail runner, focuses on functional fitness"
    ),
]


# =============================================================================
# WORKOUT DAY CONFIGURATIONS
# =============================================================================

WORKOUT_SPLITS = [
    {"day": 1, "name": "Day 1: Upper Body", "muscles": ["chest", "back", "shoulders"]},
    {"day": 2, "name": "Day 2: Lower Body", "muscles": ["legs", "glutes"]},
    {"day": 3, "name": "Day 3: Push", "muscles": ["chest", "shoulders", "triceps"]},
    {"day": 4, "name": "Day 4: Pull", "muscles": ["back", "biceps"]},
    {"day": 5, "name": "Day 5: Legs", "muscles": ["legs", "glutes", "core"]},
    {"day": 6, "name": "Day 6: Arms & Core", "muscles": ["biceps", "triceps", "core"]},
]


# =============================================================================
# PROGRESSIVE UNLOCK LOGIC
# =============================================================================

def get_unlock_tier(workouts_completed: int) -> FoundationTier:
    """Determine max tier based on workouts completed"""
    if workouts_completed < 3:
        return FoundationTier.ESSENTIAL
    elif workouts_completed < 6:
        return FoundationTier.FUNDAMENTAL
    elif workouts_completed < 12:
        return FoundationTier.STANDARD
    else:
        return FoundationTier.VARIETY


def get_variety_percentage(workouts_completed: int) -> float:
    """Get percentage of non-foundational exercises allowed"""
    if workouts_completed < 3:
        return 0.0
    elif workouts_completed < 6:
        return 0.1
    elif workouts_completed < 12:
        return 0.3
    else:
        return 1.0


def is_exercise_safe(exercise_name: str, injuries: List[str]) -> bool:
    """Check if exercise is safe given user's injuries"""
    exercise_lower = exercise_name.lower()
    for injury in injuries:
        if injury in INJURY_CONTRAINDICATIONS:
            for contraindicated in INJURY_CONTRAINDICATIONS[injury]:
                if contraindicated.lower() in exercise_lower:
                    return False
    return True


def get_foundational_score(exercise_name: str, exercise_tier: FoundationTier, 
                           workouts_completed: int, experience_level: str = "beginner") -> float:
    """
    Calculate foundational boost score based on experience level.
    
    ALL experience levels start with common exercises, but variety is introduced at different rates:
    - BEGINNER: Strong foundational preference for ~20 workouts
    - INTERMEDIATE: Moderate preference for ~10 workouts  
    - ADVANCED: Light preference for ~5 workouts, then full variety
    """
    level = experience_level.lower()
    
    if exercise_tier == FoundationTier.NON_FOUNDATIONAL:
        # Penalty for non-foundational - varies by experience level
        if level == "advanced":
            # Quick unlock: penalty only for first 3 workouts
            if workouts_completed < 3:
                return -40
            return 0
        elif level == "intermediate":
            # Moderate unlock: penalty tapers by workout 10
            if workouts_completed < 5:
                return -60
            elif workouts_completed < 10:
                return -25
            return 0
        else:  # beginner
            # Gradual unlock: strong preference for basics through workout 20
            if workouts_completed < 5:
                return -80
            elif workouts_completed < 10:
                return -50
            elif workouts_completed < 20:
                return -20
            return 0
    
    # Boost for foundational exercises
    tier_boost = {
        FoundationTier.ESSENTIAL: 200,
        FoundationTier.FUNDAMENTAL: 100,
        FoundationTier.STANDARD: 50,
        FoundationTier.VARIETY: 25,
    }
    
    base_boost = tier_boost.get(exercise_tier, 0)
    
    # Scale multiplier by experience level and workouts completed
    if level == "advanced":
        # Advanced users: quick taper
        if workouts_completed < 2:
            multiplier = 0.8
        elif workouts_completed < 5:
            multiplier = 0.4
        else:
            multiplier = 0.15
    elif level == "intermediate":
        # Intermediate: moderate taper
        if workouts_completed < 3:
            multiplier = 0.9
        elif workouts_completed < 8:
            multiplier = 0.5
        else:
            multiplier = 0.2
    else:  # beginner
        # Beginner: slow taper, stick to basics longer
        if workouts_completed < 5:
            multiplier = 1.0
        elif workouts_completed < 10:
            multiplier = 0.8
        elif workouts_completed < 20:
            multiplier = 0.5
        elif workouts_completed < 50:
            multiplier = 0.3
        else:
            multiplier = 0.15
    
    return base_boost * multiplier


def get_beginner_equipment_boost(equipment: str, workouts_completed: int, 
                                  experience_level: str, user_equipment: List[str]) -> float:
    """
    Equipment comfort progression based on experience level from onboarding.
    ALL users start with common equipment (machines/cables preferred), but progress at different rates:
    
    BEGINNER (10 workout transition):
      - Workouts 1-3:  Heavy machine/cable preference
      - Workouts 4-6:  Moderate preference
      - Workouts 7-10: Slight preference
      - Workout 11+:   Normal
    
    INTERMEDIATE (5 workout transition):
      - Workouts 1-2:  Moderate machine/cable preference
      - Workouts 3-5:  Slight preference
      - Workout 6+:    Normal
    
    ADVANCED (2 workout transition):
      - Workouts 1-2:  Slight machine/cable preference
      - Workout 3+:    Normal
    """
    level = experience_level.lower()
    equip_lower = equipment.lower()
    user_equip_lower = [e.lower() for e in user_equipment]
    
    has_machines = any("machine" in e for e in user_equip_lower)
    has_cables = any("cable" in e for e in user_equip_lower)
    
    def equip_boost(machine_boost, cable_boost, dumbbell_penalty=0, barbell_penalty=0):
        if "machine" in equip_lower or "lever" in equip_lower:
            return machine_boost
        elif "cable" in equip_lower:
            return cable_boost
        elif "dumbbell" in equip_lower:
            return -dumbbell_penalty
        elif "barbell" in equip_lower:
            return -barbell_penalty
        return 0
    
    # ═══════════════════════════════════════════════════════════════
    # ADVANCED: Quick 2-workout orientation, then fully open
    # ═══════════════════════════════════════════════════════════════
    if level == "advanced":
        if workouts_completed >= 2 or not (has_machines and has_cables):
            return 0
        return equip_boost(30, 20)
    
    # ═══════════════════════════════════════════════════════════════
    # INTERMEDIATE: 5-workout transition period
    # ═══════════════════════════════════════════════════════════════
    if level == "intermediate":
        if workouts_completed >= 5 or not (has_machines and has_cables):
            return 0
        if workouts_completed < 2:
            return equip_boost(80, 60, 10, 20)
        else:
            return equip_boost(30, 20)
    
    # ═══════════════════════════════════════════════════════════════
    # BEGINNER: Full 10-workout progression to build confidence
    # ═══════════════════════════════════════════════════════════════
    if workouts_completed >= 10:
        return 0
    
    if has_machines and has_cables:
        if workouts_completed < 3:
            return equip_boost(150, 120, 30, 60)
        elif workouts_completed < 6:
            return equip_boost(80, 60, -20, 30)  # negative penalty = bonus for dumbbells now
        else:
            return equip_boost(30, 20)
    elif has_cables and not has_machines:
        if workouts_completed < 5:
            if "cable" in equip_lower:
                return 100
            elif "dumbbell" in equip_lower:
                return 20
    
    return 0


# =============================================================================
# WORKOUT GENERATION SIMULATION
# =============================================================================

def generate_workout_for_user(user: TestUser, day_config: dict) -> dict:
    """Simulate generating a workout for a user"""
    workout = {
        "day": day_config["day"],
        "name": day_config["name"],
        "muscles": day_config["muscles"],
        "exercises": [],
        "scores": {
            "foundational_appropriate": 0,
            "injury_safe": 0,
            "equipment_match": 0,
            "tier_appropriate": 0,
            "total_exercises": 0,
        },
        "issues": [],
    }
    
    max_tier = get_unlock_tier(user.workouts_completed)
    variety_pct = get_variety_percentage(user.workouts_completed)
    
    # Select 5 exercises per workout
    exercise_count = 5
    selected_exercises = []
    
    for muscle in day_config["muscles"]:
        # Get available exercises from user's equipment
        available = []
        
        for equip in user.equipment:
            if equip in FOUNDATIONAL_EXERCISES:
                muscle_key = muscle
                if muscle == "glutes":
                    muscle_key = "glutes" if "glutes" in FOUNDATIONAL_EXERCISES[equip] else "legs"
                
                if muscle_key in FOUNDATIONAL_EXERCISES[equip]:
                    for ex in FOUNDATIONAL_EXERCISES[equip][muscle_key]:
                        ex_copy = ex.copy()
                        ex_copy["equipment"] = equip
                        ex_copy["muscle"] = muscle
                        available.append(ex_copy)
        
        # Also add obscure exercises for testing (should be filtered out for beginners)
        if muscle in OBSCURE_EXERCISES:
            for obscure in OBSCURE_EXERCISES[muscle]:
                available.append({
                    "name": obscure,
                    "tier": FoundationTier.NON_FOUNDATIONAL,
                    "compound": False,
                    "equipment": user.equipment[0] if user.equipment else "bodyweight",
                    "muscle": muscle,
                })
        
        # Score and sort exercises
        scored_exercises = []
        for ex in available:
            score = 100
            
            # Foundational boost/penalty (varies by experience level)
            foundational_score = get_foundational_score(
                ex["name"], 
                ex["tier"], 
                user.workouts_completed,
                user.experience_level
            )
            score += foundational_score
            
            # 🏋️ BEGINNER EQUIPMENT PREFERENCE
            # New gym users prefer: Machines > Cables > Dumbbells > Barbells
            beginner_equip_boost = get_beginner_equipment_boost(
                ex.get("equipment", ""),
                user.workouts_completed,
                user.experience_level,
                user.equipment
            )
            score += beginner_equip_boost
            
            # Compound bonus
            if ex.get("compound"):
                score += 25
            
            # Experience level adjustment
            if user.experience_level == "beginner":
                if ex["tier"] == FoundationTier.NON_FOUNDATIONAL:
                    score -= 500  # Heavy penalty
                elif ex["tier"].value > max_tier.value:
                    score -= 100
            
            # Injury check - major penalty
            if not is_exercise_safe(ex["name"], user.injuries):
                score -= 1000
            
            scored_exercises.append((ex, score))
        
        # Sort by score
        scored_exercises.sort(key=lambda x: x[1], reverse=True)
        
        # Pick top exercise for this muscle
        if scored_exercises:
            selected_exercises.append(scored_exercises[0])
    
    # Fill remaining slots
    while len(selected_exercises) < exercise_count:
        # Add more from available muscles
        for muscle in day_config["muscles"]:
            if len(selected_exercises) >= exercise_count:
                break
            for equip in user.equipment:
                if equip in FOUNDATIONAL_EXERCISES:
                    muscle_key = muscle if muscle in FOUNDATIONAL_EXERCISES[equip] else "legs"
                    if muscle_key in FOUNDATIONAL_EXERCISES[equip]:
                        for ex in FOUNDATIONAL_EXERCISES[equip][muscle_key]:
                            ex_name = ex["name"]
                            if not any(s[0]["name"] == ex_name for s in selected_exercises):
                                ex_copy = ex.copy()
                                ex_copy["equipment"] = equip
                                ex_copy["muscle"] = muscle
                                score = get_foundational_score(ex_name, ex["tier"], user.workouts_completed)
                                if is_exercise_safe(ex_name, user.injuries):
                                    selected_exercises.append((ex_copy, score + 100))
                                    break
                if len(selected_exercises) >= exercise_count:
                    break
    
    # Limit to exercise count
    selected_exercises = selected_exercises[:exercise_count]
    
    # Evaluate each exercise
    for ex, score in selected_exercises:
        exercise_result = {
            "name": ex["name"],
            "equipment": ex.get("equipment", ""),
            "muscle": ex.get("muscle", ""),
            "tier": ex["tier"].name if isinstance(ex["tier"], FoundationTier) else str(ex["tier"]),
            "score": score,
            "is_foundational": ex["tier"] != FoundationTier.NON_FOUNDATIONAL,
            "is_safe": is_exercise_safe(ex["name"], user.injuries),
            "is_tier_appropriate": ex["tier"].value <= max_tier.value if isinstance(ex["tier"], FoundationTier) else False,
            "issues": [],
        }
        
        workout["scores"]["total_exercises"] += 1
        
        # Check foundational appropriateness
        if user.workouts_completed < 5 and user.experience_level == "beginner":
            if exercise_result["is_foundational"]:
                workout["scores"]["foundational_appropriate"] += 1
            else:
                exercise_result["issues"].append("NON-FOUNDATIONAL for new beginner")
                workout["issues"].append(f"❌ {ex['name']}: Non-foundational exercise for new user")
        else:
            workout["scores"]["foundational_appropriate"] += 1
        
        # Check injury safety
        if exercise_result["is_safe"]:
            workout["scores"]["injury_safe"] += 1
        else:
            exercise_result["issues"].append(f"UNSAFE for injuries: {user.injuries}")
            workout["issues"].append(f"⚠️ {ex['name']}: Potentially unsafe for user's {user.injuries}")
        
        # Check equipment match
        workout["scores"]["equipment_match"] += 1  # Always match since we filter
        
        # Check tier appropriateness
        if exercise_result["is_tier_appropriate"] or ex["tier"] == FoundationTier.NON_FOUNDATIONAL:
            workout["scores"]["tier_appropriate"] += 1
        else:
            exercise_result["issues"].append(f"Above user's tier ({max_tier.name})")
        
        workout["exercises"].append(exercise_result)
    
    # Update user tracking
    user.workouts_completed += 1
    for ex, _ in selected_exercises:
        user.exercises_done.add(ex["name"])
    
    return workout


# =============================================================================
# SCORING AND EVALUATION
# =============================================================================

def calculate_user_scores(user: TestUser, workouts: List[dict]) -> dict:
    """Calculate overall scores for a user's workout series"""
    scores = {
        "foundational_score": 0,
        "safety_score": 0,
        "progression_score": 0,
        "variety_score": 0,
        "overall_score": 0,
        "total_possible": 0,
        "issues_count": 0,
        "details": [],
    }
    
    all_issues = []
    
    for workout in workouts:
        total_ex = workout["scores"]["total_exercises"]
        if total_ex > 0:
            # Foundational score
            found_score = workout["scores"]["foundational_appropriate"] / total_ex * 100
            scores["foundational_score"] += found_score
            
            # Safety score
            safety_score = workout["scores"]["injury_safe"] / total_ex * 100
            scores["safety_score"] += safety_score
            
            # Tier score
            tier_score = workout["scores"]["tier_appropriate"] / total_ex * 100
            scores["progression_score"] += tier_score
            
            scores["total_possible"] += 100
            
            all_issues.extend(workout["issues"])
    
    # Average out scores
    num_workouts = len(workouts)
    if num_workouts > 0:
        scores["foundational_score"] = round(scores["foundational_score"] / num_workouts, 1)
        scores["safety_score"] = round(scores["safety_score"] / num_workouts, 1)
        scores["progression_score"] = round(scores["progression_score"] / num_workouts, 1)
    
    # Variety score based on unique exercises
    expected_unique = num_workouts * 4  # Expect some overlap
    actual_unique = len(user.exercises_done)
    scores["variety_score"] = min(100, round(actual_unique / max(1, expected_unique) * 100, 1))
    
    # Overall score
    scores["overall_score"] = round(
        (scores["foundational_score"] * 0.35 +
         scores["safety_score"] * 0.35 +
         scores["progression_score"] * 0.2 +
         scores["variety_score"] * 0.1), 1
    )
    
    scores["issues_count"] = len(all_issues)
    scores["details"] = all_issues
    
    return scores


# =============================================================================
# HTML REPORT GENERATION
# =============================================================================

def generate_html_report(users: List[TestUser], all_results: dict) -> str:
    """Generate comprehensive HTML report"""
    
    html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Progressive Exercise System - Test Report</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #fff;
            padding: 20px;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { 
            text-align: center; 
            margin-bottom: 10px;
            font-size: 2.5rem;
            background: linear-gradient(90deg, #00f5d4, #00bbf9);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle {
            text-align: center;
            color: #888;
            margin-bottom: 30px;
            font-size: 1.1rem;
        }
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .summary-card {
            background: rgba(255,255,255,0.05);
            border-radius: 16px;
            padding: 20px;
            text-align: center;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .summary-card h3 {
            font-size: 2.5rem;
            margin-bottom: 5px;
        }
        .summary-card.green h3 { color: #00f5d4; }
        .summary-card.blue h3 { color: #00bbf9; }
        .summary-card.yellow h3 { color: #fee440; }
        .summary-card.red h3 { color: #f72585; }
        .summary-card p { color: #aaa; font-size: 0.9rem; }
        
        .user-card {
            background: rgba(255,255,255,0.03);
            border-radius: 20px;
            margin-bottom: 30px;
            overflow: hidden;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .user-header {
            background: linear-gradient(90deg, rgba(0,245,212,0.2), rgba(0,187,249,0.2));
            padding: 20px 25px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
        }
        .user-info h2 {
            font-size: 1.5rem;
            margin-bottom: 5px;
        }
        .user-info .details {
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
            color: #aaa;
            font-size: 0.85rem;
        }
        .user-info .details span {
            background: rgba(255,255,255,0.1);
            padding: 3px 10px;
            border-radius: 20px;
        }
        .score-badge {
            font-size: 2rem;
            font-weight: bold;
            padding: 10px 20px;
            border-radius: 12px;
            background: rgba(0,0,0,0.3);
        }
        .score-badge.excellent { color: #00f5d4; }
        .score-badge.good { color: #00bbf9; }
        .score-badge.warning { color: #fee440; }
        .score-badge.poor { color: #f72585; }
        
        .user-content { padding: 20px 25px; }
        
        .profile-section {
            background: rgba(0,0,0,0.2);
            border-radius: 12px;
            padding: 15px 20px;
            margin-bottom: 20px;
        }
        .profile-section h4 {
            color: #00bbf9;
            margin-bottom: 10px;
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .profile-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 10px;
        }
        .profile-item {
            background: rgba(255,255,255,0.05);
            padding: 10px 15px;
            border-radius: 8px;
        }
        .profile-item label {
            display: block;
            color: #888;
            font-size: 0.75rem;
            margin-bottom: 3px;
        }
        .profile-item value {
            display: block;
            font-weight: 500;
        }
        .injury-tag {
            display: inline-block;
            background: rgba(247,37,133,0.2);
            color: #f72585;
            padding: 3px 10px;
            border-radius: 20px;
            font-size: 0.8rem;
            margin-right: 5px;
        }
        .equipment-tag {
            display: inline-block;
            background: rgba(0,187,249,0.2);
            color: #00bbf9;
            padding: 3px 10px;
            border-radius: 20px;
            font-size: 0.8rem;
            margin-right: 5px;
            margin-bottom: 5px;
        }
        
        .scores-row {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 10px;
            margin-bottom: 20px;
        }
        .score-item {
            text-align: center;
            padding: 15px;
            background: rgba(0,0,0,0.2);
            border-radius: 12px;
        }
        .score-item .value {
            font-size: 1.8rem;
            font-weight: bold;
        }
        .score-item .label {
            font-size: 0.75rem;
            color: #888;
            margin-top: 5px;
        }
        
        .workouts-section h4 {
            color: #00f5d4;
            margin-bottom: 15px;
            font-size: 1rem;
        }
        .workout-day {
            background: rgba(0,0,0,0.2);
            border-radius: 12px;
            margin-bottom: 15px;
            overflow: hidden;
        }
        .workout-header {
            background: rgba(255,255,255,0.05);
            padding: 12px 15px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            cursor: pointer;
        }
        .workout-header:hover {
            background: rgba(255,255,255,0.08);
        }
        .workout-header h5 {
            font-size: 0.95rem;
        }
        .workout-tier {
            font-size: 0.75rem;
            padding: 3px 10px;
            border-radius: 20px;
            background: rgba(0,245,212,0.2);
            color: #00f5d4;
        }
        .workout-exercises {
            padding: 15px;
        }
        .exercise-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 15px;
            background: rgba(255,255,255,0.03);
            border-radius: 8px;
            margin-bottom: 8px;
        }
        .exercise-row:last-child { margin-bottom: 0; }
        .exercise-name {
            font-weight: 500;
        }
        .exercise-meta {
            display: flex;
            gap: 10px;
            align-items: center;
        }
        .tier-badge {
            font-size: 0.7rem;
            padding: 2px 8px;
            border-radius: 10px;
        }
        .tier-badge.essential { background: rgba(0,245,212,0.3); color: #00f5d4; }
        .tier-badge.fundamental { background: rgba(0,187,249,0.3); color: #00bbf9; }
        .tier-badge.standard { background: rgba(254,228,64,0.3); color: #fee440; }
        .tier-badge.variety { background: rgba(144,190,109,0.3); color: #90be6d; }
        .tier-badge.non_foundational { background: rgba(247,37,133,0.3); color: #f72585; }
        
        .issue-badge {
            font-size: 0.7rem;
            padding: 2px 8px;
            border-radius: 10px;
            background: rgba(247,37,133,0.3);
            color: #f72585;
        }
        .safe-badge {
            font-size: 0.7rem;
            padding: 2px 8px;
            border-radius: 10px;
            background: rgba(0,245,212,0.3);
            color: #00f5d4;
        }
        
        .issues-list {
            background: rgba(247,37,133,0.1);
            border: 1px solid rgba(247,37,133,0.3);
            border-radius: 12px;
            padding: 15px;
            margin-top: 15px;
        }
        .issues-list h5 {
            color: #f72585;
            margin-bottom: 10px;
        }
        .issues-list ul {
            list-style: none;
            padding-left: 0;
        }
        .issues-list li {
            padding: 5px 0;
            color: #f7a;
            font-size: 0.85rem;
        }
        
        .legend {
            background: rgba(255,255,255,0.05);
            border-radius: 16px;
            padding: 20px;
            margin-bottom: 30px;
        }
        .legend h3 {
            margin-bottom: 15px;
            color: #00bbf9;
        }
        .legend-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        .legend-item {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .legend-color {
            width: 30px;
            height: 30px;
            border-radius: 8px;
        }
        
        .collapsible-content {
            max-height: 0;
            overflow: hidden;
            transition: max-height 0.3s ease-out;
        }
        .collapsible-content.open {
            max-height: 2000px;
        }
        
        .toggle-btn {
            background: rgba(0,187,249,0.2);
            border: none;
            color: #00bbf9;
            padding: 8px 15px;
            border-radius: 8px;
            cursor: pointer;
            font-size: 0.85rem;
            margin-bottom: 15px;
        }
        .toggle-btn:hover {
            background: rgba(0,187,249,0.3);
        }
        
        @media (max-width: 768px) {
            .user-header { flex-direction: column; align-items: flex-start; }
            .scores-row { grid-template-columns: repeat(2, 1fr); }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏋️ Progressive Exercise System Test Report</h1>
        <p class="subtitle">Testing 14 users × 6 workout days = 84 total workouts simulated</p>
"""
    
    # Calculate summary stats
    total_score = sum(r["scores"]["overall_score"] for r in all_results.values()) / len(all_results)
    total_issues = sum(r["scores"]["issues_count"] for r in all_results.values())
    passing_users = sum(1 for r in all_results.values() if r["scores"]["overall_score"] >= 80)
    
    # Add summary cards
    html += f"""
        <div class="summary-grid">
            <div class="summary-card green">
                <h3>{total_score:.1f}%</h3>
                <p>Average Overall Score</p>
            </div>
            <div class="summary-card blue">
                <h3>{passing_users}/14</h3>
                <p>Users Passing (≥80%)</p>
            </div>
            <div class="summary-card yellow">
                <h3>84</h3>
                <p>Total Workouts Generated</p>
            </div>
            <div class="summary-card {'green' if total_issues < 20 else 'red'}">
                <h3>{total_issues}</h3>
                <p>Total Issues Found</p>
            </div>
        </div>
        
        <div class="legend">
            <h3>📊 Scoring Legend</h3>
            <div class="legend-grid">
                <div class="legend-item">
                    <div class="legend-color" style="background: rgba(0,245,212,0.5);"></div>
                    <div><strong>Essential</strong> - Core exercises everyone should know</div>
                </div>
                <div class="legend-item">
                    <div class="legend-color" style="background: rgba(0,187,249,0.5);"></div>
                    <div><strong>Fundamental</strong> - Common gym exercises</div>
                </div>
                <div class="legend-item">
                    <div class="legend-color" style="background: rgba(254,228,64,0.5);"></div>
                    <div><strong>Standard</strong> - Good variety exercises</div>
                </div>
                <div class="legend-item">
                    <div class="legend-color" style="background: rgba(247,37,133,0.5);"></div>
                    <div><strong>Non-Foundational</strong> - Should NOT appear for beginners</div>
                </div>
            </div>
        </div>
"""
    
    # Add each user's results
    for user in users:
        result = all_results[user.id]
        scores = result["scores"]
        workouts = result["workouts"]
        
        # Determine score color
        overall = scores["overall_score"]
        if overall >= 90:
            score_class = "excellent"
        elif overall >= 80:
            score_class = "good"
        elif overall >= 60:
            score_class = "warning"
        else:
            score_class = "poor"
        
        html += f"""
        <div class="user-card">
            <div class="user-header">
                <div class="user-info">
                    <h2>👤 User {user.id}: {user.name}</h2>
                    <div class="details">
                        <span>Age {user.age}</span>
                        <span>{user.gender.title()}</span>
                        <span>{user.experience_level.title()}</span>
                        <span>{user.fitness_goal.title()}</span>
                        <span>{user.workout_environment.title()}</span>
                    </div>
                </div>
                <div class="score-badge {score_class}">{overall}%</div>
            </div>
            
            <div class="user-content">
                <div class="profile-section">
                    <h4>User Profile & Situation</h4>
                    <p style="color: #ccc; margin-bottom: 15px;"><em>"{user.special_situation}"</em></p>
                    <div class="profile-grid">
                        <div class="profile-item">
                            <label>Weight</label>
                            <value>{user.weight_lbs} lbs</value>
                        </div>
                        <div class="profile-item">
                            <label>Equipment</label>
                            <value>{"".join(f'<span class="equipment-tag">{e}</span>' for e in user.equipment)}</value>
                        </div>
                        <div class="profile-item">
                            <label>Injuries/Limitations</label>
                            <value>{"".join(f'<span class="injury-tag">{i}</span>' for i in user.injuries) if user.injuries else '<span style="color:#888">None</span>'}</value>
                        </div>
                    </div>
                </div>
                
                <div class="scores-row">
                    <div class="score-item">
                        <div class="value" style="color: {'#00f5d4' if scores['foundational_score'] >= 80 else '#f72585'};">{scores['foundational_score']}%</div>
                        <div class="label">Foundational Score</div>
                    </div>
                    <div class="score-item">
                        <div class="value" style="color: {'#00f5d4' if scores['safety_score'] >= 90 else '#fee440' if scores['safety_score'] >= 70 else '#f72585'};">{scores['safety_score']}%</div>
                        <div class="label">Safety Score</div>
                    </div>
                    <div class="score-item">
                        <div class="value" style="color: {'#00f5d4' if scores['progression_score'] >= 80 else '#fee440'};">{scores['progression_score']}%</div>
                        <div class="label">Progression Score</div>
                    </div>
                    <div class="score-item">
                        <div class="value" style="color: #00bbf9;">{scores['variety_score']}%</div>
                        <div class="label">Variety Score</div>
                    </div>
                </div>
                
                <div class="workouts-section">
                    <h4>📅 6-Day Workout Progression</h4>
"""
        
        for workout in workouts:
            tier_at_workout = get_unlock_tier(workout["day"] - 1)
            variety_at_workout = get_variety_percentage(workout["day"] - 1)
            
            html += f"""
                    <div class="workout-day">
                        <div class="workout-header" onclick="this.nextElementSibling.classList.toggle('open')">
                            <h5>{workout['name']}</h5>
                            <span class="workout-tier">Tier: {tier_at_workout.name} ({int(variety_at_workout*100)}% variety)</span>
                        </div>
                        <div class="collapsible-content">
                            <div class="workout-exercises">
"""
            
            for ex in workout["exercises"]:
                tier_class = ex["tier"].lower().replace("_", "-")
                issues_html = ""
                if ex["issues"]:
                    issues_html = f'<span class="issue-badge">⚠️ {ex["issues"][0][:20]}...</span>'
                elif ex["is_safe"]:
                    issues_html = '<span class="safe-badge">✓ Safe</span>'
                
                html += f"""
                                <div class="exercise-row">
                                    <span class="exercise-name">{ex['name']}</span>
                                    <div class="exercise-meta">
                                        <span class="tier-badge {tier_class}">{ex['tier']}</span>
                                        {issues_html}
                                    </div>
                                </div>
"""
            
            html += """
                            </div>
                        </div>
                    </div>
"""
        
        # Add issues if any
        if scores["issues_count"] > 0:
            html += f"""
                <div class="issues-list">
                    <h5>⚠️ Issues Found ({scores['issues_count']})</h5>
                    <ul>
"""
            for issue in scores["details"][:10]:  # Show first 10
                html += f"                        <li>{issue}</li>\n"
            if scores["issues_count"] > 10:
                html += f"                        <li>... and {scores['issues_count'] - 10} more</li>\n"
            html += """
                    </ul>
                </div>
"""
        
        html += """
                </div>
            </div>
        </div>
"""
    
    # Add summary table
    html += """
        <div class="user-card">
            <div class="user-header">
                <div class="user-info">
                    <h2>📊 Complete Scorecard Summary</h2>
                </div>
            </div>
            <div class="user-content">
                <table style="width: 100%; border-collapse: collapse;">
                    <thead>
                        <tr style="background: rgba(255,255,255,0.1);">
                            <th style="padding: 12px; text-align: left;">User</th>
                            <th style="padding: 12px; text-align: center;">Experience</th>
                            <th style="padding: 12px; text-align: center;">Injuries</th>
                            <th style="padding: 12px; text-align: center;">Foundation</th>
                            <th style="padding: 12px; text-align: center;">Safety</th>
                            <th style="padding: 12px; text-align: center;">Progression</th>
                            <th style="padding: 12px; text-align: center;">Overall</th>
                            <th style="padding: 12px; text-align: center;">Issues</th>
                        </tr>
                    </thead>
                    <tbody>
"""
    
    for user in users:
        result = all_results[user.id]
        scores = result["scores"]
        
        overall_color = "#00f5d4" if scores["overall_score"] >= 90 else "#00bbf9" if scores["overall_score"] >= 80 else "#fee440" if scores["overall_score"] >= 60 else "#f72585"
        
        html += f"""
                        <tr style="border-bottom: 1px solid rgba(255,255,255,0.1);">
                            <td style="padding: 12px;">{user.id}. {user.name}</td>
                            <td style="padding: 12px; text-align: center;">{user.experience_level}</td>
                            <td style="padding: 12px; text-align: center;">{', '.join(user.injuries) if user.injuries else '—'}</td>
                            <td style="padding: 12px; text-align: center;">{scores['foundational_score']}%</td>
                            <td style="padding: 12px; text-align: center;">{scores['safety_score']}%</td>
                            <td style="padding: 12px; text-align: center;">{scores['progression_score']}%</td>
                            <td style="padding: 12px; text-align: center; font-weight: bold; color: {overall_color};">{scores['overall_score']}%</td>
                            <td style="padding: 12px; text-align: center;">{scores['issues_count']}</td>
                        </tr>
"""
    
    html += """
                    </tbody>
                </table>
            </div>
        </div>
"""
    
    # Footer
    html += f"""
        <div style="text-align: center; padding: 40px; color: #666;">
            <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p>Progressive Exercise System Test Suite v1.0</p>
        </div>
    </div>
    
    <script>
        // Auto-open first workout for each user
        document.querySelectorAll('.workout-day:first-child .collapsible-content').forEach(el => el.classList.add('open'));
    </script>
</body>
</html>
"""
    
    return html


# =============================================================================
# MAIN EXECUTION
# =============================================================================

def main():
    print("=" * 60)
    print("Progressive Exercise System - Test Suite")
    print("=" * 60)
    print(f"\nTesting {len(TEST_USERS)} users × 6 workout days = {len(TEST_USERS) * 6} workouts\n")
    
    all_results = {}
    
    for user in TEST_USERS:
        print(f"\n{'─' * 50}")
        print(f"User {user.id}: {user.name} ({user.experience_level}, {user.fitness_goal})")
        print(f"Equipment: {', '.join(user.equipment)}")
        print(f"Injuries: {', '.join(user.injuries) if user.injuries else 'None'}")
        print(f"Situation: {user.special_situation}")
        
        # Reset user for fresh test
        user.workouts_completed = 0
        user.exercises_done = set()
        
        workouts = []
        
        for day_config in WORKOUT_SPLITS:
            workout = generate_workout_for_user(user, day_config)
            workouts.append(workout)
            
            print(f"\n  Day {day_config['day']}: {day_config['name']}")
            print(f"    Tier: {get_unlock_tier(user.workouts_completed - 1).name}")
            for ex in workout["exercises"]:
                status = "✓" if not ex["issues"] else "⚠"
                print(f"    {status} {ex['name']} [{ex['tier']}]")
        
        # Calculate scores
        scores = calculate_user_scores(user, workouts)
        
        all_results[user.id] = {
            "user": user,
            "workouts": workouts,
            "scores": scores,
        }
        
        print(f"\n  SCORES: Foundation={scores['foundational_score']}% | "
              f"Safety={scores['safety_score']}% | "
              f"Overall={scores['overall_score']}%")
    
    # Generate HTML report
    print("\n" + "=" * 60)
    print("Generating HTML Report...")
    
    html_content = generate_html_report(TEST_USERS, all_results)
    
    output_path = "/Users/josephreed/Desktop/Workout App/progressive_exercise_test_report.html"
    with open(output_path, "w") as f:
        f.write(html_content)
    
    print(f"✅ Report saved to: {output_path}")
    
    # Print summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    
    total_score = sum(r["scores"]["overall_score"] for r in all_results.values()) / len(all_results)
    passing = sum(1 for r in all_results.values() if r["scores"]["overall_score"] >= 80)
    total_issues = sum(r["scores"]["issues_count"] for r in all_results.values())
    
    print(f"\nAverage Overall Score: {total_score:.1f}%")
    print(f"Users Passing (≥80%): {passing}/{len(TEST_USERS)}")
    print(f"Total Issues Found: {total_issues}")
    
    return output_path


if __name__ == "__main__":
    main()
