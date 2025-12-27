#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════════════════════════
COMPREHENSIVE AUTO-GEN WORKOUT AUDIT SYSTEM
═══════════════════════════════════════════════════════════════════════════════

This script performs an exhaustive audit of the workout auto-generation system.

It creates 20 unique user profiles with diverse characteristics and generates
2 workouts per user (40 total workouts), then critically analyzes every single
exercise selection to ensure the auto-gen is producing correct, safe, and
strategic workouts.

NO FAKE DATA - Uses actual exercise database and real selection logic.

Author: Comprehensive Audit System
Date: December 2024
"""

import os
import json
import random
import math
from datetime import datetime, date
from typing import List, Dict, Set, Tuple, Optional, Any
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from enum import Enum
import re

# Supabase connection
from supabase import create_client

# PDF Generation
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter, A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.platypus import ListFlowable, ListItem
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY

# ═══════════════════════════════════════════════════════════════════════════════
# SUPABASE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

def fetch_exercises_from_supabase(batch_size: int = 1000, offset: int = 0) -> List[Dict]:
    """Fetch exercises from Supabase database"""
    response = supabase.table('exercises').select('*').range(offset, offset + batch_size - 1).execute()
    return response.data if response.data else []

# ═══════════════════════════════════════════════════════════════════════════════
# ENUMS AND DATA CLASSES
# ═══════════════════════════════════════════════════════════════════════════════

class ExperienceLevel(Enum):
    BEGINNER = "Beginner"
    INTERMEDIATE = "Intermediate"
    ADVANCED = "Advanced"

class FitnessGoal(Enum):
    # The 6 goals from app onboarding (NewOnboardingView.swift)
    BUILD_MUSCLE = "Build Muscle"       # 💪 Gain size & strength
    LOSE_WEIGHT = "Lose Weight"         # 🔥 Burn fat & get lean
    GET_STRONGER = "Get Stronger"       # 🏋️ Increase max lifts
    STAY_ACTIVE = "Stay Active"         # ⚡ General fitness
    BUILD_ENDURANCE = "Build Endurance" # 🏃 Improve stamina
    IMPROVE_HEALTH = "Improve Health"   # ❤️ Overall wellness

class WorkoutLocation(Enum):
    HOME = "Home"
    GYM = "Gym"
    OUTDOOR = "Outdoor"

class BodyType(Enum):
    ECTOMORPH = "Ectomorph"  # Lean, long limbs
    MESOMORPH = "Mesomorph"  # Athletic, muscular
    ENDOMORPH = "Endomorph"  # Broader, stores fat easily

class Gender(Enum):
    MALE = "Male"
    FEMALE = "Female"
    OTHER = "Other"

class LimitationSeverity(Enum):
    """Severity levels for limitations - mirrors Swift LimitationSeverity"""
    SKIP_COMPLETELY = "skip_completely"       # Hard exclusion
    STRETCHING_ONLY = "stretching_only"       # Only stretch/mobility exercises
    LIGHT_WORK_ONLY = "light_only"            # No heavy compounds
    BE_CAREFUL = "be_careful"                 # Penalize risky, boost safe

class LimitationArea(Enum):
    """Body areas that can have limitations - mirrors Swift LimitationArea"""
    LOWER_BACK = "Lower Back"
    UPPER_BACK = "Upper Back"
    SHOULDERS = "Shoulders"
    KNEES = "Knees"
    HIPS = "Hips"
    NECK = "Neck"
    WRISTS = "Wrists"
    ELBOWS = "Elbows"
    ANKLES = "Ankles"
    OTHER = "Other"

class SpinalLoad(Enum):
    """Spinal loading level - mirrors Swift"""
    NONE = "none"
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"

class ImpactLevel(Enum):
    """Impact level - mirrors Swift"""
    NONE = "none"
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"

class OverheadWork(Enum):
    """Overhead work intensity - mirrors Swift"""
    NONE = "none"
    PARTIAL = "partial"
    FULL = "full"

class KneeFlexionDepth(Enum):
    """Knee flexion depth - mirrors Swift"""
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"

@dataclass
class ExerciseRiskMetadata:
    """Exercise risk metadata - mirrors Swift ExerciseRiskMetadata
    Used for metadata-driven limitation filtering instead of hardcoded exercise names"""
    spinal_load: SpinalLoad = SpinalLoad.NONE
    unsupported_torso: bool = False
    hip_hinge_demand: bool = False
    overhead_work: OverheadWork = OverheadWork.NONE
    knee_flexion_depth: KneeFlexionDepth = KneeFlexionDepth.LOW
    impact_level: ImpactLevel = ImpactLevel.NONE
    is_machine_supported: bool = False
    is_chest_supported: bool = False
    is_stretch_or_mobility: bool = False
    is_seated: bool = False
    is_lying: bool = False
    # Shoulder stress flags
    upright_row_like: bool = False
    behind_neck: bool = False
    guillotine: bool = False
    heavy_dip: bool = False
    # Other flags
    neck_stress: bool = False
    elbow_stress: bool = False
    high_balance_demand: bool = False
    high_wrist_extension: bool = False

@dataclass
class Injury:
    """Represents a user's physical limitation"""
    area: str  # e.g., "Shoulder", "Lower Back", "Knee"
    severity: str  # "skip_completely", "light_only", "stretching_only", "be_careful"
    description: str

@dataclass
class UserProfile:
    """Represents a complete user profile for testing"""
    id: int
    name: str
    age: int
    gender: Gender
    weight_lbs: float
    height_inches: int
    body_type: BodyType
    experience_level: ExperienceLevel
    fitness_goal: FitnessGoal
    workout_location: WorkoutLocation
    available_equipment: List[str]
    injuries: List[Injury]
    workouts_completed: int  # For progressive unlock logic
    preferred_workout_duration: int  # minutes
    available_days_per_week: int
    notes: str  # Special considerations

@dataclass
class ExerciseAnalysis:
    """Analysis of a single exercise selection"""
    exercise_name: str
    equipment: str
    primary_muscles: List[str]
    secondary_muscles: List[str]
    is_equipment_valid: bool
    equipment_reason: str
    is_muscle_match: bool
    muscle_reason: str
    is_appropriate_difficulty: bool
    difficulty_reason: str
    is_injury_safe: bool
    injury_reason: str
    is_practical: bool
    practical_reason: str
    selection_score: float
    selection_reasoning: str
    issues: List[str]
    is_approved: bool

@dataclass
class WorkoutAnalysis:
    """Complete analysis of a generated workout"""
    user_id: int
    user_name: str
    workout_number: int
    target_muscles: List[str]
    exercises: List[ExerciseAnalysis]
    equipment_accuracy: float
    muscle_accuracy: float
    variety_score: float
    difficulty_appropriateness: float
    injury_safety_score: float
    practicality_score: float
    overall_score: float
    grade: str
    critical_issues: List[str]
    warnings: List[str]
    recommendations: List[str]

# ═══════════════════════════════════════════════════════════════════════════════
# 20 DIVERSE USER PROFILES
# ═══════════════════════════════════════════════════════════════════════════════

def create_test_user_profiles() -> List[UserProfile]:
    """
    Creates 20 NEW GYM-ONLY user profiles for comprehensive gym workout testing.
    BATCH 4: Brand new users with diverse demographics.
    """
    profiles = []
    
    # USER 1: Insurance Agent - New to Gym
    profiles.append(UserProfile(
        id=1,
        name="Brandon Hayes",
        age=32,
        gender=Gender.MALE,
        weight_lbs=185,
        height_inches=71,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[],
        workouts_completed=6,
        preferred_workout_duration=45,
        available_days_per_week=4,
        notes="Wants to build muscle, new to gym"
    ))
    
    # USER 2: Marketing Executive
    profiles.append(UserProfile(
        id=2,
        name="Vanessa Liu",
        age=29,
        gender=Gender.FEMALE,
        weight_lbs=135,
        height_inches=65,
        body_type=BodyType.ECTOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[],
        workouts_completed=60,
        preferred_workout_duration=40,
        available_days_per_week=4,
        notes="Wants toned physique for professional image"
    ))
    
    # USER 3: Construction Worker
    profiles.append(UserProfile(
        id=3,
        name="Miguel Santos",
        age=38,
        gender=Gender.MALE,
        weight_lbs=205,
        height_inches=70,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.GET_STRONGER,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[
            Injury("Lower Back", "be_careful", "Heavy lifting at work")
        ],
        workouts_completed=180,
        preferred_workout_duration=50,
        available_days_per_week=4,
        notes="Physically demanding job, needs gym for structured training"
    ))
    
    # USER 4: Dental Hygienist
    profiles.append(UserProfile(
        id=4,
        name="Courtney Bell",
        age=26,
        gender=Gender.FEMALE,
        weight_lbs=125,
        height_inches=64,
        body_type=BodyType.ECTOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.STAY_ACTIVE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables"],
        injuries=[],
        workouts_completed=12,
        preferred_workout_duration=35,
        available_days_per_week=3,
        notes="First time gym member, wants to get fit"
    ))
    
    # USER 5: Retired Teacher
    profiles.append(UserProfile(
        id=5,
        name="Harold Jackson",
        age=64,
        gender=Gender.MALE,
        weight_lbs=195,
        height_inches=69,
        body_type=BodyType.ENDOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables"],
        injuries=[
            Injury("Knees", "be_careful", "Arthritis"),
            Injury("Shoulders", "be_careful", "Age-related stiffness")
        ],
        workouts_completed=45,
        preferred_workout_duration=40,
        available_days_per_week=4,
        notes="Retired, focused on health maintenance"
    ))
    
    # USER 6: College Soccer Player
    profiles.append(UserProfile(
        id=6,
        name="Destiny Clark",
        age=20,
        gender=Gender.FEMALE,
        weight_lbs=140,
        height_inches=67,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.GET_STRONGER,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[],
        workouts_completed=85,
        preferred_workout_duration=55,
        available_days_per_week=5,
        notes="D1 athlete needs power and explosiveness"
    ))
    
    # USER 7: Postpartum Mom
    profiles.append(UserProfile(
        id=7,
        name="Ashley Martinez",
        age=31,
        gender=Gender.FEMALE,
        weight_lbs=155,
        height_inches=66,
        body_type=BodyType.ENDOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[
            Injury("Core/Abdomen", "be_careful", "Diastasis recti postpartum")
        ],
        workouts_completed=25,
        preferred_workout_duration=35,
        available_days_per_week=3,
        notes="6 months postpartum, rebuilding core strength"
    ))
    
    # USER 8: Truck Driver
    profiles.append(UserProfile(
        id=8,
        name="Wayne Foster",
        age=45,
        gender=Gender.MALE,
        weight_lbs=265,
        height_inches=72,
        body_type=BodyType.ENDOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables"],
        injuries=[
            Injury("Lower Back", "be_careful", "Sitting all day driving")
        ],
        workouts_completed=8,
        preferred_workout_duration=30,
        available_days_per_week=3,
        notes="Sedentary job, starting fitness journey"
    ))
    
    # USER 9: Physical Therapist
    profiles.append(UserProfile(
        id=9,
        name="Jordan Wright",
        age=28,
        gender=Gender.FEMALE,
        weight_lbs=138,
        height_inches=68,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[],
        workouts_completed=200,
        preferred_workout_duration=60,
        available_days_per_week=5,
        notes="Fitness professional, understands anatomy"
    ))
    
    # USER 10: IT Manager
    profiles.append(UserProfile(
        id=10,
        name="David Chen",
        age=34,
        gender=Gender.MALE,
        weight_lbs=175,
        height_inches=70,
        body_type=BodyType.ECTOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[
            Injury("Neck", "be_careful", "Computer posture issues")
        ],
        workouts_completed=70,
        preferred_workout_duration=50,
        available_days_per_week=4,
        notes="Desk job, wants to gain muscle mass"
    ))
    
    # USER 11: Elementary School Teacher
    profiles.append(UserProfile(
        id=11,
        name="Nicole Thompson",
        age=42,
        gender=Gender.FEMALE,
        weight_lbs=165,
        height_inches=65,
        body_type=BodyType.ENDOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables"],
        injuries=[],
        workouts_completed=15,
        preferred_workout_duration=40,
        available_days_per_week=3,
        notes="Busy schedule, needs efficient workouts"
    ))
    
    # USER 12: Semi-Pro Boxer
    profiles.append(UserProfile(
        id=12,
        name="Marcus Robinson",
        age=24,
        gender=Gender.MALE,
        weight_lbs=165,
        height_inches=71,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.GET_STRONGER,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[],
        workouts_completed=250,
        preferred_workout_duration=65,
        available_days_per_week=6,
        notes="Combat athlete, needs power and endurance"
    ))
    
    # USER 13: Nurse (Night Shift)
    profiles.append(UserProfile(
        id=13,
        name="Stephanie Moore",
        age=33,
        gender=Gender.FEMALE,
        weight_lbs=148,
        height_inches=66,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[
            Injury("Feet", "be_careful", "12-hour shifts on feet")
        ],
        workouts_completed=55,
        preferred_workout_duration=40,
        available_days_per_week=3,
        notes="Works nights, gym helps with energy"
    ))
    
    # USER 14: High School Football Coach
    profiles.append(UserProfile(
        id=14,
        name="Tyler Jenkins",
        age=36,
        gender=Gender.MALE,
        weight_lbs=210,
        height_inches=74,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.GET_STRONGER,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[
            Injury("Shoulders", "be_careful", "Old football injury")
        ],
        workouts_completed=300,
        preferred_workout_duration=60,
        available_days_per_week=5,
        notes="Former player, leads by example"
    ))
    
    # USER 15: Stay-at-Home Dad
    profiles.append(UserProfile(
        id=15,
        name="Ryan Miller",
        age=37,
        gender=Gender.MALE,
        weight_lbs=190,
        height_inches=71,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.STAY_ACTIVE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[],
        workouts_completed=50,
        preferred_workout_duration=35,
        available_days_per_week=3,
        notes="Works out during kids' school hours"
    ))
    
    # USER 16: Bank Manager
    profiles.append(UserProfile(
        id=16,
        name="Patricia Wilson",
        age=48,
        gender=Gender.FEMALE,
        weight_lbs=158,
        height_inches=64,
        body_type=BodyType.ENDOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.STAY_ACTIVE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables"],
        injuries=[
            Injury("Knees", "be_careful", "Occasional pain when climbing stairs")
        ],
        workouts_completed=10,
        preferred_workout_duration=35,
        available_days_per_week=3,
        notes="New to fitness, wants to feel stronger"
    ))
    
    # USER 17: Graphic Designer
    profiles.append(UserProfile(
        id=17,
        name="Alex Rivera",
        age=25,
        gender=Gender.MALE,
        weight_lbs=155,
        height_inches=68,
        body_type=BodyType.ECTOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[],
        workouts_completed=18,
        preferred_workout_duration=45,
        available_days_per_week=4,
        notes="Skinny guy wanting to bulk up"
    ))
    
    # USER 18: Real Estate Agent
    profiles.append(UserProfile(
        id=18,
        name="Michelle Brooks",
        age=39,
        gender=Gender.FEMALE,
        weight_lbs=142,
        height_inches=67,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Cables", "Machines", "Dumbbells"],
        injuries=[],
        workouts_completed=80,
        preferred_workout_duration=45,
        available_days_per_week=4,
        notes="Active lifestyle, maintains fitness"
    ))
    
    # USER 19: Recovering from Hip Surgery
    profiles.append(UserProfile(
        id=19,
        name="James Patterson",
        age=55,
        gender=Gender.MALE,
        weight_lbs=195,
        height_inches=72,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.STAY_ACTIVE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables"],
        injuries=[
            Injury("Hips", "light_only", "Hip replacement 6 months ago")
        ],
        workouts_completed=30,
        preferred_workout_duration=40,
        available_days_per_week=4,
        notes="CRITICAL: Hip replacement - careful with hip flexion"
    ))
    
    # USER 20: Competitive Swimmer
    profiles.append(UserProfile(
        id=20,
        name="Olivia Taylor",
        age=21,
        gender=Gender.FEMALE,
        weight_lbs=145,
        height_inches=69,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.GET_STRONGER,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[],
        workouts_completed=190,
        preferred_workout_duration=55,
        available_days_per_week=5,
        notes="Swimmer - needs upper body and lat strength"
    ))
    
    return profiles

# ═══════════════════════════════════════════════════════════════════════════════
# WORKOUT SPLITS FOR TESTING
# ═══════════════════════════════════════════════════════════════════════════════

WORKOUT_SPLITS = [
    {
        "name": "Push Day",
        "muscles": ["Chest", "Shoulders", "Triceps"],
        "description": "Horizontal and vertical pressing movements"
    },
    {
        "name": "Pull Day",
        "muscles": ["Back", "Biceps"],
        "description": "All pulling movements"
    },
    {
        "name": "Leg Day",
        "muscles": ["Quads", "Hamstrings", "Glutes", "Calves"],
        "description": "Lower body focus"
    },
    {
        "name": "Chest & Triceps",
        "muscles": ["Chest", "Triceps"],
        "description": "Classic push pairing"
    },
    {
        "name": "Back & Biceps",
        "muscles": ["Back", "Biceps"],
        "description": "Classic pull pairing"
    },
    {
        "name": "Upper Body",
        "muscles": ["Chest", "Back", "Shoulders"],
        "description": "Full upper body"
    },
    {
        "name": "Lower Body",
        "muscles": ["Quads", "Hamstrings", "Glutes"],
        "description": "Full lower body"
    },
    {
        "name": "Shoulders & Arms",
        "muscles": ["Shoulders", "Biceps", "Triceps"],
        "description": "Arms and delts focus"
    },
    {
        "name": "Full Body",
        "muscles": ["Chest", "Back", "Legs", "Core"],
        "description": "Hit everything"
    },
    {
        "name": "Core Focus",
        "muscles": ["Core", "Abs"],
        "description": "Midsection focus"
    }
]

# ═══════════════════════════════════════════════════════════════════════════════
# EXERCISE FILTERING AND SELECTION LOGIC
# (Mirrors Swift implementation)
# ═══════════════════════════════════════════════════════════════════════════════

# Muscle group expansion - matches Swift SmartExerciseSelectionEngine
MUSCLE_GROUP_EXPANSION = {
    "chest": ["chest", "pectorals", "pecs", "upper chest", "lower chest", "mid chest"],
    "back": ["back", "lats", "upper back", "lower back", "traps", "rhomboids", "latissimus dorsi", "middle back"],
    "lats": ["lats", "latissimus dorsi"],
    "shoulders": ["shoulders", "delts", "deltoids", "front delts", "rear delts", "side delts", "anterior deltoid", "lateral deltoid", "posterior deltoid"],
    "arms": ["arms", "biceps", "triceps", "forearms", "brachialis"],
    "biceps": ["biceps", "brachialis"],
    "triceps": ["triceps"],
    "legs": ["legs", "quads", "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors", "hip flexors"],
    "quads": ["quads", "quadriceps"],
    "hamstrings": ["hamstrings"],
    "glutes": ["glutes", "gluteus", "gluteus maximus"],
    "calves": ["calves", "calf", "gastrocnemius", "soleus"],
    "core": ["core", "abs", "abdominals", "obliques", "lower abs", "upper abs", "transverse abdominis"],
    "abs": ["abs", "abdominals", "lower abs", "upper abs"],
}

# Floor exercises to exclude for gym users (but NOT core - core is normal at gym)
FLOOR_EXERCISES_TO_EXCLUDE = [
    "bear crawl", "inchworm",
    "burpee", "mountain climber",  # Cardio-style floor work
    "renegade",  # Complex combo
    "fire hydrant", "clam",  # Rehab-style - use machines instead
    "hip thrust on floor", "hip raise on floor"  # Use hip thrust machine at gym
]

# Core exercises that ARE appropriate at the gym (on mats in stretching area)
GYM_APPROPRIATE_CORE = [
    "plank", "dead bug", "bird dog", "hollow", 
    "crunch", "sit-up", "situp", "leg raise",
    "pallof", "anti-rotation", "ab wheel", "rollout",
    "russian twist", "woodchop", "wood chop",
    "side plank", "oblique", "superman"
]

# Gym-appropriate bodyweight exercises
GYM_APPROPRIATE_BODYWEIGHT = [
    "pull-up", "pullup", "chin-up", "chinup",
    "dip", "hanging", "muscle up", "muscle-up",
    "inverted row"
]

# Heavy compound exercises (for injury filtering)
HEAVY_COMPOUND_EXERCISES = [
    "deadlift", "rdl", "romanian deadlift", "sumo deadlift", "stiff leg",
    "squat", "front squat", "back squat", "goblet squat", "hack squat",
    "bench press", "bench", "chest press", "incline press", "decline press",
    "overhead press", "military press", "shoulder press", "push press",
    "barbell row", "bent over row", "pendlay row", "t-bar row",
    "clean", "snatch", "jerk", "power clean", "hang clean",
    "hip thrust", "good morning", "leg press"
]

# Obscure exercises to deprioritize
OBSCURE_PATTERNS = [
    "under table", "couch", "doorway", "towel", "broomstick",
    "suitcase", "grocery", "water bottle", "backpack", "gallon",
    "bottle weighted", "chair dip", "bed", "door frame", "stairs"
]

# Advanced exercises to avoid for beginners
ADVANCED_EXERCISES = [
    "handstand", "planche", "muscle up", "muscle-up", "iron cross",
    "human flag", "front lever", "back lever", "l-sit", "v-sit",
    "one arm pull", "one arm push", "pistol squat", "dragon flag",
    "hollow back press", "maltese", "victorian", "clean", "snatch", "jerk"
]

# Foundational exercises (from FoundationalExerciseDatabase)
ESSENTIAL_FOUNDATIONAL = [
    "barbell bench press", "barbell squat", "barbell deadlift", "barbell bent over row",
    "dumbbell bench press", "dumbbell row", "dumbbell shoulder press", "dumbbell bicep curl", "goblet squat",
    "cable fly", "seated cable row", "cable tricep pushdown", "lat pulldown",
    "machine chest press", "machine shoulder press", "leg press", "machine row",
    "push up", "bodyweight squat", "plank", "bodyweight lunge",
    "kettlebell swing", "kettlebell goblet squat"
]

# ═══════════════════════════════════════════════════════════════════════════════
# FOUNDATIONAL EXERCISE WHITELIST - Safe, repeatable, progressive exercises
# These are the exercises that should be prioritized for "foundational" mode
# ═══════════════════════════════════════════════════════════════════════════════
FOUNDATIONAL_CHEST_EXERCISES = [
    "bench press", "dumbbell bench press", "smith bench press", 
    "decline bench press", "smith decline bench press", "decline dumbbell press",
    "incline bench press", "incline dumbbell press", "smith incline bench press",
    "machine chest press", "lever chest press", "seated chest press",
    "cable fly", "cable crossover", "pec deck", "machine fly", "lever pec deck fly",
    "dumbbell fly", "decline fly", "incline fly",
    "assisted dip", "dip", "lever graviton assisted dip", "lever seated dip",
    "push up", "incline push up", "decline push up",
]

FOUNDATIONAL_BACK_EXERCISES = [
    "lat pulldown", "wide grip lat pulldown", "close grip pulldown",
    "seated cable row", "machine row", "lever row", "chest supported row",
    "barbell row", "dumbbell row", "one arm dumbbell row", "t-bar row",
    "pull up", "chin up", "assisted pull up", "assisted chin up",
    "cable straight arm pulldown", "pullover",
]

FOUNDATIONAL_SHOULDER_EXERCISES = [
    "machine shoulder press", "smith shoulder press", "lever shoulder press",
    "dumbbell shoulder press", "seated dumbbell press",
    "lateral raise", "dumbbell lateral raise", "cable lateral raise", "machine lateral raise",
    "front raise", "cable front raise",
    "face pull", "rear delt fly", "reverse fly", "rear delt machine",
]

FOUNDATIONAL_LEG_EXERCISES = [
    "leg press", "hack squat", "smith squat", "machine squat",
    "barbell squat", "goblet squat", "front squat",
    "leg extension", "machine leg extension", "lever leg extension",
    "leg curl", "lying leg curl", "seated leg curl", "machine leg curl",
    "hip thrust", "barbell hip thrust", "machine hip thrust",
    "walking lunge", "reverse lunge", "split squat", "bulgarian split squat",
    "romanian deadlift", "stiff leg deadlift",
    "calf raise", "standing calf raise", "seated calf raise", "machine calf raise",
    "glute bridge", "cable pull through",
]

FOUNDATIONAL_ARM_EXERCISES = [
    "barbell curl", "dumbbell curl", "ez bar curl", "preacher curl", "cable curl",
    "hammer curl", "incline dumbbell curl", "machine curl",
    "tricep pushdown", "cable pushdown", "rope pushdown", "v-bar pushdown",
    "skull crusher", "lying tricep extension", "overhead tricep extension",
    "dip", "close grip bench press", "machine dip",
]

# Combine all foundational exercises
ALL_FOUNDATIONAL_EXERCISES = (
    FOUNDATIONAL_CHEST_EXERCISES + 
    FOUNDATIONAL_BACK_EXERCISES + 
    FOUNDATIONAL_SHOULDER_EXERCISES + 
    FOUNDATIONAL_LEG_EXERCISES + 
    FOUNDATIONAL_ARM_EXERCISES
)

# ═══════════════════════════════════════════════════════════════════════════════
# RISKY EXERCISE BLACKLIST - Exercises to avoid or heavily penalize
# These exercises are risky, complex, or impractical for foundational training
# ═══════════════════════════════════════════════════════════════════════════════
RISKY_EXERCISES = [
    # Shoulder-risky pressing variations
    "guillotine", "behind neck", "behind the neck", "wide grip overhead",
    
    # Complex combination movements (bad for tracking/progression)
    "renegade row", "push up row", "push up and row", "row push up",
    "pullover to press", "pullover press", "press to pullover",
    "curl to press", "press to curl", "squat to press", "press squat",
    "lunge curl", "curl lunge", "deadlift to row", "row deadlift",
    "burpee", "man maker", "devil press",
    
    # Anti-rotation under load (lower back stress)
    "plank row", "plank with row", "bird dog row", 
    
    # Unstable/coordination-heavy (hard to progress)
    "single arm push up", "archer push up", "typewriter push up",
    "pistol squat", "single leg squat",
    
    # Grip variations that add complexity without benefit for beginners
    "reverse grip decline", "reverse grip incline", 
    "jm bench press", "jm press",
    
    # Complex plank variations
    "plank lateral raise", "plank front raise", "plank reach",
]

# ═══════════════════════════════════════════════════════════════════════════════
# LOWER BACK STRESS EXERCISES - Exercises to avoid/penalize for back issues
# These exercises put significant stress on the lower back
# ═══════════════════════════════════════════════════════════════════════════════
LOWER_BACK_STRESS_EXERCISES = [
    # High stress - avoid completely
    "renegade row", "bird dog row", "plank row",  # Anti-rotation under load
    "bent over row", "barbell row", "pendlay row",  # Unsupported bent position
    "deadlift", "conventional deadlift", "sumo deadlift",  # Heavy hip hinge
    "good morning", "seated good morning",  # Direct lower back load
    "back extension", "hyperextension", "45 degree back extension",
    "snatch", "clean", "clean and jerk",  # Olympic lifts
    
    # Moderate stress - penalize but allow with caution
    "t-bar row", "dumbbell row",  # Can be done with support
    "romanian deadlift", "rdl", "stiff leg deadlift",  # Lighter hinge
]

# Exercises that are SAFE alternatives for lower back issues
LOWER_BACK_SAFE_ALTERNATIVES = [
    # Supported rows (chest/machine support)
    "chest supported row", "chest-supported row", "machine row", 
    "lever row", "seated cable row", "seated row",
    
    # Machine leg work (takes back out of equation)
    "leg press", "hack squat", "machine squat",
    "leg extension", "leg curl", "machine leg curl",
    
    # Supported pressing
    "machine chest press", "smith bench press", "cable press",
    
    # Core work that doesn't stress lower back
    "dead bug", "pallof press", "bird dog", "plank",
]

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTION: Check if exercise is foundational
# ═══════════════════════════════════════════════════════════════════════════════
def is_foundational_exercise(exercise_name: str) -> bool:
    """Check if exercise is in the foundational whitelist"""
    name_lower = exercise_name.lower()
    return any(found.lower() in name_lower for found in ALL_FOUNDATIONAL_EXERCISES)

def is_risky_exercise(exercise_name: str) -> bool:
    """Check if exercise is in the risky blacklist"""
    name_lower = exercise_name.lower()
    return any(risky.lower() in name_lower for risky in RISKY_EXERCISES)

def is_lower_back_stress_exercise(exercise_name: str) -> bool:
    """Check if exercise puts significant stress on lower back"""
    name_lower = exercise_name.lower()
    return any(stress.lower() in name_lower for stress in LOWER_BACK_STRESS_EXERCISES)

def is_lower_back_safe_exercise(exercise_name: str) -> bool:
    """Check if exercise is a safe alternative for lower back issues"""
    name_lower = exercise_name.lower()
    return any(safe.lower() in name_lower for safe in LOWER_BACK_SAFE_ALTERNATIVES)

# ═══════════════════════════════════════════════════════════════════════════════
# METADATA-DRIVEN LIMITATION FILTERING SYSTEM
# Mirrors Swift LimitationFilterEngine.swift, ExerciseMetadataClassifier.swift,
# and LimitationRuleTables.swift
# ═══════════════════════════════════════════════════════════════════════════════

def classify_exercise_metadata(exercise_name: str, equipment: str = "") -> ExerciseRiskMetadata:
    """
    Classify an exercise and return its risk metadata.
    Mirrors Swift ExerciseMetadataClassifier.shared.classify()
    NO HARDCODED EXERCISE NAMES - uses keyword patterns
    """
    name = exercise_name.lower()
    equip = equipment.lower()
    
    def contains_any(text: str, keywords: List[str]) -> bool:
        return any(kw in text for kw in keywords)
    
    # Spinal Load
    if contains_any(name, ["deadlift", "good morning", "back squat", "front squat", 
                          "barbell row", "bent over row", "barbell bent", "renegade", "atlas"]):
        spinal_load = SpinalLoad.HIGH
    elif contains_any(name, ["squat", "rdl", "romanian", "row", "lunge", "overhead press", "military press"]):
        if contains_any(name, ["machine", "seated", "lying", "chest supported", "incline"]):
            spinal_load = SpinalLoad.LOW
        else:
            spinal_load = SpinalLoad.MODERATE
    elif contains_any(name, ["seated", "lying", "machine", "cable", "incline", "chest supported"]):
        spinal_load = SpinalLoad.LOW
    elif contains_any(equip, ["machine", "cable", "smith"]):
        spinal_load = SpinalLoad.LOW
    else:
        spinal_load = SpinalLoad.NONE
    
    # Unsupported torso
    unsupported_torso = (contains_any(name, ["bent over", "bent-over", "renegade", "pendlay", "barbell row"]) and 
                        not contains_any(name, ["chest supported", "seal row", "incline bench row"]))
    if contains_any(name, ["good morning", "stiff leg", "romanian"]) and "machine" not in name:
        unsupported_torso = True
    
    # Hip hinge
    hip_hinge = contains_any(name, ["deadlift", "rdl", "romanian", "good morning", "hip hinge", 
                                     "swing", "bent over", "bent-over", "stiff leg", "pull through"])
    
    # Overhead work
    if contains_any(name, ["overhead press", "military press", "shoulder press", "push press", "jerk", 
                          "snatch", "pull-up", "pullup", "chin-up", "chinup"]):
        if contains_any(name, ["pulldown", "lat pull"]):
            overhead_work = OverheadWork.PARTIAL
        else:
            overhead_work = OverheadWork.FULL
    elif contains_any(name, ["incline press", "high incline", "arnold"]):
        overhead_work = OverheadWork.PARTIAL
    else:
        overhead_work = OverheadWork.NONE
    
    # Knee flexion depth
    if contains_any(name, ["deep squat", "atg", "ass to grass", "full squat", "pistol", "sissy squat"]):
        knee_flexion = KneeFlexionDepth.HIGH
    elif contains_any(name, ["squat", "lunge", "leg press", "hack squat", "split squat"]):
        knee_flexion = KneeFlexionDepth.MODERATE
    else:
        knee_flexion = KneeFlexionDepth.LOW
    
    # Impact level
    if contains_any(name, ["jump", "plyo", "box jump", "burpee", "clap pushup", "depth jump", "bound"]):
        impact = ImpactLevel.HIGH
    elif contains_any(name, ["step up", "split jump", "lunge jump", "skater"]):
        impact = ImpactLevel.MODERATE
    else:
        impact = ImpactLevel.NONE
    
    # Machine support
    is_machine = contains_any(name, ["machine", "cable", "smith", "assisted"]) or \
                 contains_any(equip, ["machine", "cable", "smith"])
    
    # Chest support
    is_chest_supported = contains_any(name, ["chest supported", "chest-supported", "seal row", 
                                             "prone row", "incline bench row", "t-bar row chest"])
    
    # Seated/lying
    is_seated = contains_any(name, ["seated", "sitting"])
    is_lying = contains_any(name, ["lying", "prone", "supine", "bench press", "floor press", 
                                   "leg curl machine", "leg extension"])
    
    # Stretch/mobility
    is_stretch = contains_any(name, ["stretch", "mobility", "foam roll", "flexibility", "yoga"])
    
    # Shoulder stress flags
    upright_row = contains_any(name, ["upright row", "high pull", "face pull to external"])
    behind_neck = contains_any(name, ["behind neck", "behind-neck", "btn"])
    guillotine = contains_any(name, ["guillotine", "neck press"])
    heavy_dip = contains_any(name, ["dip", "chest dip"]) and "tricep dip machine" not in name
    
    # Other stress flags
    neck_stress = contains_any(name, ["shrug", "neck", "wrestler bridge", "neck curl"])
    elbow_stress = contains_any(name, ["skullcrusher", "skull crusher", "jm press", "close grip bench"])
    high_balance = contains_any(name, ["single leg", "pistol", "one leg", "bulgarian", "bosu", "single-leg"])
    high_wrist = contains_any(name, ["front squat clean grip", "push-up", "pushup", "handstand", "planche"])
    
    return ExerciseRiskMetadata(
        spinal_load=spinal_load,
        unsupported_torso=unsupported_torso,
        hip_hinge_demand=hip_hinge,
        overhead_work=overhead_work,
        knee_flexion_depth=knee_flexion,
        impact_level=impact,
        is_machine_supported=is_machine,
        is_chest_supported=is_chest_supported,
        is_stretch_or_mobility=is_stretch,
        is_seated=is_seated,
        is_lying=is_lying,
        upright_row_like=upright_row,
        behind_neck=behind_neck,
        guillotine=guillotine,
        heavy_dip=heavy_dip,
        neck_stress=neck_stress,
        elbow_stress=elbow_stress,
        high_balance_demand=high_balance,
        high_wrist_extension=high_wrist
    )

def get_limitation_area(area_str: str) -> LimitationArea:
    """Map string to LimitationArea enum"""
    area = area_str.lower()
    if "lower back" in area or "low back" in area:
        return LimitationArea.LOWER_BACK
    if "upper back" in area:
        return LimitationArea.UPPER_BACK
    if "shoulder" in area:
        return LimitationArea.SHOULDERS
    if "knee" in area:
        return LimitationArea.KNEES
    if "hip" in area:
        return LimitationArea.HIPS
    if "neck" in area:
        return LimitationArea.NECK
    if "wrist" in area:
        return LimitationArea.WRISTS
    if "elbow" in area:
        return LimitationArea.ELBOWS
    if "ankle" in area:
        return LimitationArea.ANKLES
    return LimitationArea.OTHER

def get_limitation_severity(severity_str: str) -> LimitationSeverity:
    """Map string to LimitationSeverity enum"""
    severity = severity_str.lower()
    if "skip" in severity or "avoid" in severity:
        return LimitationSeverity.SKIP_COMPLETELY
    if "stretch" in severity:
        return LimitationSeverity.STRETCHING_ONLY
    if "light" in severity:
        return LimitationSeverity.LIGHT_WORK_ONLY
    return LimitationSeverity.BE_CAREFUL

def does_metadata_affect_area(metadata: ExerciseRiskMetadata, area: LimitationArea) -> bool:
    """Check if exercise metadata indicates it affects a body area"""
    if area == LimitationArea.LOWER_BACK:
        return (metadata.spinal_load in [SpinalLoad.MODERATE, SpinalLoad.HIGH] or
                metadata.unsupported_torso or
                metadata.hip_hinge_demand)
    if area == LimitationArea.UPPER_BACK:
        return metadata.unsupported_torso
    if area == LimitationArea.SHOULDERS:
        return (metadata.upright_row_like or metadata.behind_neck or 
                metadata.guillotine or metadata.heavy_dip or
                metadata.overhead_work != OverheadWork.NONE)
    if area == LimitationArea.KNEES:
        return (metadata.knee_flexion_depth in [KneeFlexionDepth.MODERATE, KneeFlexionDepth.HIGH] or
                metadata.impact_level in [ImpactLevel.MODERATE, ImpactLevel.HIGH])
    if area == LimitationArea.HIPS:
        return metadata.hip_hinge_demand
    if area == LimitationArea.NECK:
        return metadata.neck_stress
    if area == LimitationArea.WRISTS:
        return metadata.high_wrist_extension
    if area == LimitationArea.ELBOWS:
        return metadata.elbow_stress
    if area == LimitationArea.ANKLES:
        return metadata.impact_level in [ImpactLevel.MODERATE, ImpactLevel.HIGH] or metadata.high_balance_demand
    return False

def evaluate_skip_completely(metadata: ExerciseRiskMetadata, area: LimitationArea) -> Tuple[bool, str]:
    """Evaluate if exercise should be excluded for Skip Completely severity"""
    if area == LimitationArea.LOWER_BACK:
        if metadata.spinal_load == SpinalLoad.HIGH:
            return True, "High spinal load"
        if metadata.unsupported_torso and metadata.hip_hinge_demand:
            return True, "Unsupported hinge movement"
        if metadata.unsupported_torso:
            return True, "Unsupported bent-over position"
    if area == LimitationArea.SHOULDERS:
        if metadata.overhead_work == OverheadWork.FULL:
            return True, "Full overhead work"
        if metadata.upright_row_like:
            return True, "Upright row pattern"
        if metadata.behind_neck:
            return True, "Behind neck movement"
        if metadata.guillotine:
            return True, "Guillotine/extreme ROM"
        if metadata.heavy_dip:
            return True, "Heavy dip (shoulder extension)"
    if area == LimitationArea.KNEES:
        if metadata.knee_flexion_depth == KneeFlexionDepth.HIGH:
            return True, "Deep knee flexion"
        if metadata.impact_level in [ImpactLevel.MODERATE, ImpactLevel.HIGH]:
            return True, "High impact"
    if area == LimitationArea.HIPS:
        if metadata.hip_hinge_demand and metadata.spinal_load in [SpinalLoad.MODERATE, SpinalLoad.HIGH]:
            return True, "Deep hip hinge"
    if area == LimitationArea.NECK:
        if metadata.neck_stress:
            return True, "Direct neck stress"
    if area == LimitationArea.WRISTS:
        if metadata.high_wrist_extension:
            return True, "High wrist extension"
    if area == LimitationArea.ELBOWS:
        if metadata.elbow_stress:
            return True, "Direct elbow stress"
    if area == LimitationArea.ANKLES:
        if metadata.impact_level in [ImpactLevel.MODERATE, ImpactLevel.HIGH]:
            return True, "High impact"
        if metadata.high_balance_demand:
            return True, "High balance demand"
    return False, ""

def evaluate_light_work_only(metadata: ExerciseRiskMetadata, area: LimitationArea) -> Tuple[bool, int, str]:
    """Evaluate for Light Work Only: returns (should_exclude, penalty, reason)"""
    # Check for hard exclusions first
    if area == LimitationArea.LOWER_BACK:
        if metadata.spinal_load == SpinalLoad.HIGH:
            return True, 0, "Spinal load too high for light work"
        if metadata.unsupported_torso and metadata.hip_hinge_demand:
            return True, 0, "Unsupported hinge too risky"
    if area == LimitationArea.SHOULDERS:
        if metadata.overhead_work == OverheadWork.FULL:
            return True, 0, "Full overhead too stressful"
        if metadata.heavy_dip or metadata.behind_neck or metadata.guillotine or metadata.upright_row_like:
            return True, 0, "High-risk shoulder position"
    if area == LimitationArea.KNEES:
        if metadata.knee_flexion_depth == KneeFlexionDepth.HIGH and not metadata.is_machine_supported:
            return True, 0, "Deep flexion under load"
        if metadata.impact_level in [ImpactLevel.MODERATE, ImpactLevel.HIGH]:
            return True, 0, "Impact too high"
    
    # Calculate penalty/boost for allowed exercises
    penalty = 0
    reason = ""
    
    if area == LimitationArea.LOWER_BACK:
        if metadata.is_machine_supported:
            penalty -= 50
            reason = "Machine-supported (back-friendly)"
        if metadata.is_chest_supported:
            penalty -= 80
            reason = "Chest-supported position"
        if metadata.is_seated and metadata.spinal_load in [SpinalLoad.NONE, SpinalLoad.LOW]:
            penalty -= 40
            reason = "Seated position"
        if metadata.is_lying:
            penalty -= 60
            reason = "Lying position"
        if metadata.spinal_load == SpinalLoad.MODERATE:
            penalty += 100
            reason = "Moderate spinal load - careful"
        if metadata.unsupported_torso:
            penalty += 150
            reason = "Unsupported torso"
    elif area == LimitationArea.SHOULDERS:
        if metadata.is_machine_supported:
            penalty -= 50
            reason = "Machine-supported"
        if metadata.overhead_work == OverheadWork.PARTIAL:
            penalty += 80
            reason = "Partial overhead work"
    elif area == LimitationArea.KNEES:
        if metadata.is_machine_supported:
            penalty -= 60
            reason = "Machine-supported"
        if metadata.knee_flexion_depth == KneeFlexionDepth.LOW:
            penalty -= 40
            reason = "Low knee flexion"
        if metadata.is_lying:
            penalty -= 50
            reason = "Lying position"
        if metadata.knee_flexion_depth == KneeFlexionDepth.MODERATE and not metadata.is_machine_supported:
            penalty += 80
            reason = "Moderate flexion without support"
        if metadata.high_balance_demand:
            penalty += 100
            reason = "High balance demand"
    
    return False, penalty, reason

def evaluate_be_careful(metadata: ExerciseRiskMetadata, area: LimitationArea) -> Tuple[int, str]:
    """Evaluate for Be Careful: returns (penalty, reason) - positive = bad, negative = good"""
    penalty = 0
    reason = ""
    
    if area == LimitationArea.LOWER_BACK:
        if metadata.is_machine_supported:
            penalty -= 30
            reason = "Machine-supported"
        if metadata.is_chest_supported:
            penalty -= 50
            reason = "Chest-supported"
        if metadata.is_lying:
            penalty -= 40
            reason = "Lying position"
        if metadata.spinal_load == SpinalLoad.MODERATE:
            penalty += 40
            reason = "Moderate spinal load"
        if metadata.spinal_load == SpinalLoad.HIGH:
            penalty += 150
            reason = "High spinal load"
        if metadata.unsupported_torso:
            penalty += 80
            reason = "Unsupported torso"
        if metadata.hip_hinge_demand and not metadata.is_machine_supported and not metadata.is_chest_supported:
            penalty += 60
            reason = "Hip hinge (free weight)"
    elif area == LimitationArea.SHOULDERS:
        if metadata.is_machine_supported:
            penalty -= 30
            reason = "Machine-supported"
        if metadata.upright_row_like:
            penalty += 100
            reason = "Upright row pattern"
        if metadata.behind_neck:
            penalty += 150
            reason = "Behind neck"
        if metadata.guillotine:
            penalty += 150
            reason = "Guillotine press"
        if metadata.heavy_dip:
            penalty += 80
            reason = "Heavy dip"
        if metadata.overhead_work != OverheadWork.NONE:
            penalty += 60
            reason = "Overhead work"
    elif area == LimitationArea.KNEES:
        if metadata.is_machine_supported:
            penalty -= 40
            reason = "Machine-supported"
        if metadata.knee_flexion_depth == KneeFlexionDepth.LOW:
            penalty -= 30
            reason = "Low knee flexion"
        if metadata.impact_level in [ImpactLevel.MODERATE, ImpactLevel.HIGH]:
            penalty += 120
            reason = "Impact/plyometric"
        if metadata.knee_flexion_depth == KneeFlexionDepth.HIGH:
            penalty += 80
            reason = "Deep knee flexion"
        if metadata.high_balance_demand:
            penalty += 60
            reason = "High balance demand"
    elif area == LimitationArea.HIPS:
        if metadata.is_machine_supported:
            penalty -= 30
            reason = "Machine-supported"
        if metadata.hip_hinge_demand and metadata.spinal_load in [SpinalLoad.MODERATE, SpinalLoad.HIGH]:
            penalty += 80
            reason = "Deep hip hinge"
    elif area == LimitationArea.NECK:
        if metadata.neck_stress:
            penalty += 100
            reason = "Direct neck stress"
    elif area == LimitationArea.ANKLES:
        if metadata.is_seated:
            penalty -= 30
            reason = "Seated position"
        if metadata.impact_level in [ImpactLevel.MODERATE, ImpactLevel.HIGH]:
            penalty += 80
            reason = "Impact"
        if metadata.high_balance_demand:
            penalty += 50
            reason = "High balance demand"
    
    return penalty, reason

def apply_metadata_limitation_filter(exercise_name: str, equipment: str, 
                                     injuries: List[Injury]) -> Tuple[bool, int, str]:
    """
    Apply metadata-driven limitation filtering.
    Returns: (should_exclude, penalty, reason)
    This is the main entry point for the new metadata-driven system.
    Mirrors Swift WorkoutLimitationFilter.shared.filterForWorkout()
    """
    if not injuries:
        return False, 0, ""
    
    metadata = classify_exercise_metadata(exercise_name, equipment)
    total_penalty = 0
    reasons = []
    
    for injury in injuries:
        area = get_limitation_area(injury.area)
        severity = get_limitation_severity(injury.severity)
        
        # Check if exercise affects this area
        if not does_metadata_affect_area(metadata, area):
            continue
        
        # Apply severity-specific rules
        if severity == LimitationSeverity.SKIP_COMPLETELY:
            should_exclude, reason = evaluate_skip_completely(metadata, area)
            if should_exclude:
                return True, 0, f"[SKIP] {area.value}: {reason}"
            # Even if not excluded, heavy penalty for skip-completely areas
            total_penalty += 300
            reasons.append(f"Exercise stresses {area.value}")
            
        elif severity == LimitationSeverity.STRETCHING_ONLY:
            if not metadata.is_stretch_or_mobility:
                return True, 0, f"[STRETCH ONLY] Only stretching allowed for {area.value}"
            
        elif severity == LimitationSeverity.LIGHT_WORK_ONLY:
            should_exclude, penalty, reason = evaluate_light_work_only(metadata, area)
            if should_exclude:
                return True, 0, f"[LIGHT] {area.value}: {reason}"
            total_penalty += penalty
            if reason:
                reasons.append(reason)
                
        elif severity == LimitationSeverity.BE_CAREFUL:
            penalty, reason = evaluate_be_careful(metadata, area)
            total_penalty += penalty
            if reason:
                reasons.append(reason)
    
    return False, total_penalty, "; ".join(reasons) if reasons else ""

def expand_target_muscles(target_muscles: List[str]) -> Set[str]:
    """Expand target muscles to include sub-muscles"""
    expanded = set(m.lower() for m in target_muscles)
    for target in target_muscles:
        target_lower = target.lower()
        if target_lower in MUSCLE_GROUP_EXPANSION:
            expanded.update(MUSCLE_GROUP_EXPANSION[target_lower])
    return expanded

def get_injury_exercise_penalties(exercise_name: str, injuries: List[Injury], equipment: str = "") -> int:
    """
    Get score penalty for exercises based on user's injuries.
    Returns a penalty score (negative number) or 0 if no penalty.
    
    NOW USES METADATA-DRIVEN FILTERING: This function delegates to the new
    apply_metadata_limitation_filter() system for comprehensive, tag-based filtering.
    
    Legacy keyword-based checks are kept as fallback for edge cases.
    """
    # Use new metadata-driven system first
    _, metadata_penalty, _ = apply_metadata_limitation_filter(exercise_name, equipment, injuries)
    
    # Return as negative (our scoring system expects negative penalties)
    if metadata_penalty > 0:
        return -metadata_penalty
    elif metadata_penalty < 0:  # Boost (safe exercise)
        return -metadata_penalty  # Return as positive boost
    
    # Legacy fallback for edge cases not caught by metadata
    name_lower = exercise_name.lower()
    penalty = 0
    
    for injury in injuries:
        area_lower = injury.area.lower()
        severity = injury.severity.lower() if hasattr(injury, 'severity') else 'be_careful'
        
        # SHOULDER INJURIES - Avoid dips, upright rows, high pulls, stacked overhead pressing
        if "shoulder" in area_lower:
            # Hard avoid dips for shoulder issues
            if "dip" in name_lower:
                penalty -= 300  # Effectively blocks dips
            
            # CRITICAL: Upright rows are shoulder irritators - block for shoulder issues
            if "upright row" in name_lower or "upright pull" in name_lower:
                penalty -= 350  # Higher than dips - very common irritator
            
            # CRITICAL: High pulls stress shoulders - block for shoulder issues
            if "high pull" in name_lower:
                penalty -= 350  # Block high pulls
            
            # Penalize overhead pressing (prefer machine/neutral grip)
            if "overhead" in name_lower or "military" in name_lower:
                penalty -= 150
            
            # Penalize barbell pressing (prefer machine/dumbbell)
            if "barbell" in name_lower and "press" in name_lower:
                penalty -= 100
            
            # Boost neutral grip and machine presses
            if "neutral grip" in name_lower or "neutral-grip" in name_lower:
                penalty += 50  # This is a boost, not penalty
            if "machine" in name_lower and "press" in name_lower:
                penalty += 30
        
        # KNEE INJURIES - Avoid plyo and jumping movements
        if "knee" in area_lower:
            # Hard avoid plyo/jumping
            plyo_patterns = ["jump", "hop", "plyo", "explosive", "bound", "skip"]
            if any(p in name_lower for p in plyo_patterns):
                penalty -= 300  # Effectively blocks plyo
            
            # Penalize deep lunges and side lunges
            if "side lunge" in name_lower or "lateral lunge" in name_lower:
                penalty -= 200
            if "change" in name_lower and "lunge" in name_lower:  # Change Plyo Side Lunge
                penalty -= 250
            
            # Prefer controlled unilateral (reverse lunge, step-up, split squat)
            if "reverse lunge" in name_lower or "rear lunge" in name_lower:
                penalty += 30
            if "step up" in name_lower or "step-up" in name_lower:
                penalty += 30
            if "split squat" in name_lower:
                penalty += 20
        
        # ═══════════════════════════════════════════════════════════════════════════════
        # LOW BACK INJURIES - COMPREHENSIVE handling
        # This is critical: lower back issues are common and need strict enforcement
        # ═══════════════════════════════════════════════════════════════════════════════
        if "lower back" in area_lower or "low back" in area_lower or "back" in area_lower:
            # CRITICAL: Anti-rotation exercises under load - VERY BAD for lower back
            # Renegade rows, plank rows, etc. require heavy core bracing under fatigue
            anti_rotation_patterns = [
                "renegade row", "renegade", "plank row", "plank with row",
                "bird dog row", "push up row", "push up and row", "row push up",
                "plank lateral raise", "plank front raise", "plank reach"
            ]
            if any(p in name_lower for p in anti_rotation_patterns):
                penalty -= 400  # BLOCK these for any back issues
            
            # Heavy bent-over positions - high lower back stress
            bent_over_patterns = [
                "bent over", "bent-over", "pendlay row", "barbell row",
                "t-bar row", "meadows row"
            ]
            if any(p in name_lower for p in bent_over_patterns):
                penalty -= 250  # Heavy penalty - prefer supported rows
            
            # Deadlifts and hinges - significant lower back load
            hinge_patterns = [
                "deadlift", "dead lift", "rdl", "romanian",
                "stiff leg", "good morning", "hyperextension", "back extension"
            ]
            if any(p in name_lower for p in hinge_patterns):
                penalty -= 300  # Block heavy hinges for back issues
            
            # Olympic lifts - too dynamic for back issues
            olympic_patterns = ["clean", "snatch", "jerk", "power clean"]
            if any(p in name_lower for p in olympic_patterns):
                penalty -= 350  # Block olympic lifts
            
            # Unsupported core work that loads the spine
            if "sit up" in name_lower or "situp" in name_lower:
                penalty -= 150  # Penalize crunching movements
            if "crunch" in name_lower and "reverse" not in name_lower:
                penalty -= 100  # Regular crunches stress lower back
            
            # ═══════════════════════════════════════════════════════════════════════════════
            # BOOST safe alternatives for lower back issues
            # ═══════════════════════════════════════════════════════════════════════════════
            
            # Chest-supported rows are ideal
            if "chest supported" in name_lower or "chest-supported" in name_lower:
                penalty += 120  # Strong boost for supported rows
            
            # Machine rows remove lower back from equation
            if "machine row" in name_lower or "lever row" in name_lower:
                penalty += 100
            
            # Seated cable rows are safe
            if "seated" in name_lower and "row" in name_lower:
                penalty += 80
            
            # Machine work in general is safer
            if "machine" in name_lower or "lever" in name_lower:
                penalty += 50
            
            # Leg press instead of squats
            if "leg press" in name_lower or "hack squat" in name_lower:
                penalty += 70
            
            # Core exercises that don't stress lower back
            safe_core = ["dead bug", "pallof", "bird dog", "plank"]
            if any(p in name_lower for p in safe_core) and "row" not in name_lower:
                penalty += 40
    
    return penalty

def is_exercise_safe_for_injury(exercise_name: str, exercise_equipment: str, 
                                 exercise_muscles: List[str], injuries: List[Injury]) -> Tuple[bool, str]:
    """
    Check if an exercise is safe given user's injuries - HARD BLOCKS for severe injuries.
    
    NOW USES METADATA-DRIVEN FILTERING: This function uses the new
    apply_metadata_limitation_filter() system for comprehensive tag-based filtering.
    
    Legacy keyword-based checks are kept as fallback for edge cases.
    Mirrors Swift LimitationsService.filterSafeExercises()
    """
    # Use new metadata-driven system for hard exclusions
    should_exclude, _, reason = apply_metadata_limitation_filter(exercise_name, exercise_equipment, injuries)
    if should_exclude:
        return False, reason
    
    # Legacy fallback checks for edge cases
    name_lower = exercise_name.lower()
    equip_lower = exercise_equipment.lower()
    muscles_lower = [m.lower() for m in exercise_muscles if m]
    
    for injury in injuries:
        area_lower = injury.area.lower()
        severity = injury.severity.lower() if hasattr(injury, 'severity') else 'be_careful'
        
        # Map old severity names to new system
        if severity == 'mild':
            severity = 'be_careful'
        if severity == 'avoid_completely':
            severity = 'skip_completely'
        
        # For BE_CAREFUL, we use penalties (in scoring) not hard blocks
        # Only block for severe injuries or obvious contraindications
        if severity == 'be_careful':
            # Still block obvious contraindications even for mild
            if "shoulder" in area_lower and "behind neck" in name_lower:
                return False, f"Behind neck press contraindicated for shoulder issues"
            if "knee" in area_lower and ("jump squat" in name_lower or "box jump" in name_lower):
                return False, f"Jump squats contraindicated for knee issues"
            # Let penalties handle the rest for mild injuries
            continue
        
        # Define exercise patterns to avoid for each injury area (SEVERE - kept as fallback)
        injury_patterns = {
            "shoulders": ["overhead", "behind neck", "upright row"],
            "shoulder": ["overhead", "behind neck", "upright row"],
            "lower back": ["deadlift", "good morning", "bent over", "rdl", "stiff leg", "hyperextension"],
            "knees": ["squat", "lunge", "jump", "hop", "step up", "split squat"],
            "knee": ["squat", "lunge", "jump", "hop", "step up", "split squat"],
            "hips": ["squat", "lunge", "deadlift", "hip thrust", "abduct", "adduct"],
            "hip": ["squat", "lunge", "deadlift", "hip thrust", "abduct", "adduct"],
            "wrists": ["curl", "wrist", "front squat", "clean", "snatch", "push up", "press", "row", "deadlift"],
            "wrist": ["curl", "wrist", "front squat", "clean", "snatch", "push up", "press", "row", "deadlift"],
            "elbows": ["curl", "extension", "tricep", "skull crusher", "pushdown", "dip", "close grip", "press"],
            "elbow": ["curl", "extension", "tricep", "skull crusher", "pushdown", "dip", "close grip", "press"],
            "neck": ["shrug", "neck", "upright row"],
            "core/abdomen": ["crunch", "sit up", "plank", "ab", "core", "twist", "leg raise", "hollow", "v-up"],
            "core": ["crunch", "sit up", "plank", "ab", "core", "twist", "leg raise", "hollow", "v-up"],
            "chest": ["bench", "fly", "push up", "dip", "chest press", "incline", "decline"]
        }
        
        patterns = injury_patterns.get(area_lower, [])
        
        for pattern in patterns:
            if pattern in name_lower:
                if injury.severity == "avoid_completely":
                    return False, f"UNSAFE: {exercise_name} involves {pattern} - user has {injury.area} injury (avoid completely)"
                elif injury.severity == "light_only":
                    # Check if it's a heavy compound
                    if any(heavy in name_lower for heavy in HEAVY_COMPOUND_EXERCISES):
                        return False, f"UNSAFE: {exercise_name} is heavy compound - user can only do light {injury.area} work"
                elif injury.severity == "be_careful":
                    pass  # Allowed but should be noted
    
    return True, "Safe"

def get_equipment_patterns(user_equip: str) -> List[str]:
    """
    Map user-friendly equipment names to database patterns.
    User selects: "Machines", "Cables", "Barbell", "Dumbbells"
    Database has: "Lever Machine", "Cable Machine", "Chest Press Machine", etc.
    """
    equip = user_equip.lower().strip()
    
    patterns = {
        # Machines - comprehensive list of all machine types in database
        "machines": ["machine", "lever", "lever machine", "chest press machine", 
                    "leg press machine", "leg curl machine", "seated row machine",
                    "press machine", "curl machine", "row machine", "extension machine", 
                    "leg press", "hack squat", "pec deck", "pulldown", "lat machine",
                    "smith machine"],  # Note: Smith machine is also included under "machines"
        "machine": ["machine", "lever", "lever machine", "chest press machine",
                   "press machine", "curl machine", "row machine", "extension machine", 
                   "leg press", "hack squat", "pec deck"],
        # Cables - separate from machines for more specific matching
        "cables": ["cable", "cable machine", "pulley", "pulldown"],
        "cable": ["cable", "cable machine", "pulley"],
        # Barbell equipment
        "barbell": ["barbell", "bar", "olympic", "ez bar", "trap bar"],
        "barbells": ["barbell", "bar", "olympic", "ez bar", "trap bar"],
        # Dumbbells
        "dumbbells": ["dumbbell", "dumbbells", "db"],
        "dumbbell": ["dumbbell", "dumbbells", "db"],
        # Bodyweight
        "bodyweight": ["bodyweight", "body weight", ""],
        "body weight": ["bodyweight", "body weight", ""],
        # Kettlebell
        "kettlebell": ["kettlebell", "kb"],
        "kettlebells": ["kettlebell", "kb"],
        # Resistance bands
        "resistance bands": ["band", "resistance band", "resistance"],
        "resistance band": ["band", "resistance band", "resistance"],
        "bands": ["band", "resistance band", "resistance"],
        # Specialty equipment
        "trx": ["trx", "suspension"],
        "pull-up bar": ["pull-up bar", "pull up bar", "pullup bar"],
        "smith machine": ["smith machine", "smith"]
    }
    
    return patterns.get(equip, [equip])

def check_equipment_match(exercise_equipment: str, user_equipment: List[str], 
                          is_gym_user: bool) -> Tuple[bool, str]:
    """Check if exercise equipment matches user's available equipment"""
    equip_lower = exercise_equipment.lower().strip()
    user_equip_lower = [e.lower() for e in user_equipment]
    
    # Parse exercise equipment (e.g., "Bench, Barbell" -> ["bench", "barbell"])
    exercise_equip_parts = [p.strip() for p in equip_lower.split(',') if p.strip()]
    
    # Handle empty or bodyweight equipment
    is_bodyweight = not exercise_equip_parts or equip_lower == 'bodyweight' or equip_lower == ''
    
    if is_bodyweight:
        # Check if user has bodyweight in their equipment list
        if any('bodyweight' in eq or 'body weight' in eq for eq in user_equip_lower):
            return True, "Bodyweight exercise - user has bodyweight selected"
        
        # GYM USERS: Always allow gym-appropriate bodyweight exercises
        # (pull-ups, dips, core exercises are normal at gyms)
        if is_gym_user:
            return True, "Bodyweight exercise allowed for gym user (core/pull-ups/dips are standard)"
        
        return False, f"Bodyweight exercise but user doesn't have bodyweight selected"
    
    # Common items always available at gyms or home
    # NOTE: "chair", "wall", "step" are NOT included - they are home/improvised equipment
    # and should only be used when user explicitly selects them
    common_items = ["floor", "mat", "bench", "flat bench", "incline bench", 
                    "decline bench", "preacher bench", "box"]
    
    missing_equipment = []
    for req in exercise_equip_parts:
        # Skip common items
        if any(common in req for common in common_items):
            continue
        
        found = False
        
        # For each user equipment, get the patterns it matches
        for user_eq in user_equip_lower:
            patterns = get_equipment_patterns(user_eq)
            
            # Check if any pattern matches the required equipment
            for pattern in patterns:
                if pattern in req or req in pattern:
                    found = True
                    break
            
            # Also do direct string matching as fallback
            if req in user_eq or user_eq in req:
                found = True
            
            if found:
                break
        
        if not found:
            missing_equipment.append(req)
    
    if missing_equipment:
        return False, f"Missing equipment: {', '.join(missing_equipment)} - user has {user_equipment}"
    
    return True, f"Equipment match: {exercise_equipment}"

def check_gym_appropriateness(exercise_name: str, exercise_equipment: str, 
                               is_gym_user: bool) -> Tuple[bool, str]:
    """For gym users, ensure exercises are gym-appropriate (not floor/home exercises)"""
    if not is_gym_user:
        return True, "Not gym user - no gym filtering applied"
    
    name_lower = exercise_name.lower()
    equip_lower = exercise_equipment.lower()
    
    # 🚫 EXCLUDED EQUIPMENT FOR GYM - These are home/improvised items!
    # Matches Swift ExerciseFilterService.excludedEquipmentByLocation[.gym]
    GYM_EXCLUDED_EQUIPMENT = ["chair", "wall", "bottle", "improvised", "towel", "couch", 
                              "door frame", "doorway", "stairs", "step platform", "broomstick",
                              "water bottle", "gallon", "suitcase", "grocery bag"]
    
    # Check if ANY excluded equipment is in the exercise equipment list
    for excluded in GYM_EXCLUDED_EQUIPMENT:
        if excluded in equip_lower:
            return False, f"Excluded gym equipment '{excluded}' - use machines/cables/barbells instead"
    
    # Also check exercise name for home workout patterns
    HOME_WORKOUT_PATTERNS = ["on chair", "chair dip", "bed supported", "couch", "doorway", 
                             "under table", "wall sit", "against wall"]
    for pattern in HOME_WORKOUT_PATTERNS:
        if pattern in name_lower:
            return False, f"Home workout pattern '{pattern}' not appropriate for gym"
    
    is_bodyweight = equip_lower == 'bodyweight' or equip_lower == '' or not equip_lower.strip()
    
    if not is_bodyweight:
        return True, "Uses gym equipment - appropriate"
    
    # Check if it's a gym-appropriate CORE exercise first (core work is normal at gyms)
    is_gym_core = any(pattern in name_lower for pattern in GYM_APPROPRIATE_CORE)
    
    if is_gym_core:
        return True, f"Gym-appropriate core exercise: {exercise_name}"
    
    # Check if it's gym-appropriate bodyweight
    is_gym_appropriate = any(pattern in name_lower for pattern in GYM_APPROPRIATE_BODYWEIGHT)
    
    if is_gym_appropriate:
        return True, f"Gym-appropriate bodyweight: {exercise_name}"
    
    # Check if it's a floor exercise that should be excluded
    is_floor_exercise = any(pattern in name_lower for pattern in FLOOR_EXERCISES_TO_EXCLUDE)
    
    if is_floor_exercise:
        return False, f"Floor exercise '{exercise_name}' not appropriate for gym user"
    
    return False, f"Bodyweight exercise '{exercise_name}' not typical for gym - user has gym equipment"

def check_difficulty_appropriateness(exercise_name: str, user: UserProfile) -> Tuple[bool, str]:
    """Check if exercise difficulty matches user's experience level"""
    name_lower = exercise_name.lower()
    
    is_advanced_exercise = any(adv in name_lower for adv in ADVANCED_EXERCISES)
    is_foundational = any(found in name_lower for found in ESSENTIAL_FOUNDATIONAL)
    
    if user.experience_level == ExperienceLevel.BEGINNER:
        if is_advanced_exercise:
            return False, f"Advanced exercise '{exercise_name}' not appropriate for beginner"
        # For beginners with <10 workouts, prefer foundational exercises
        if user.workouts_completed < 10 and not is_foundational:
            return True, f"Not foundational, but acceptable for beginner"  # Warning, not error
        return True, "Appropriate for beginner"
    
    elif user.experience_level == ExperienceLevel.INTERMEDIATE:
        if is_advanced_exercise:
            # Intermediates can do some advanced exercises
            return True, f"Advanced exercise acceptable for intermediate user"
        return True, "Appropriate for intermediate"
    
    else:  # Advanced
        return True, "Advanced user can handle any exercise"

def check_weight_appropriateness(exercise_name: str, user: UserProfile) -> Tuple[bool, str]:
    """Check if exercise is appropriate for user's body weight/type"""
    name_lower = exercise_name.lower()
    
    # For very heavy users (300+ lbs), certain exercises may be problematic
    if user.weight_lbs >= 300:
        problematic_for_heavy = [
            "pull-up", "pullup", "chin-up", "chinup", "dip",
            "box jump", "jump", "hop", "burpee", "mountain climber"
        ]
        if any(p in name_lower for p in problematic_for_heavy):
            if user.experience_level == ExperienceLevel.BEGINNER:
                return False, f"Exercise '{exercise_name}' too challenging for 300lb beginner - needs regression"
            else:
                return True, "Heavy user but experienced - may need modifications"
    
    # For elderly users, high-impact exercises are problematic
    if user.age >= 60:
        high_impact = ["jump", "hop", "burpee", "plyo", "explosive", "sprint"]
        if any(p in name_lower for p in high_impact):
            return False, f"High-impact exercise '{exercise_name}' not appropriate for user age {user.age}"
    
    return True, "Appropriate for user's body"

def check_practicality(exercise_name: str, user: UserProfile) -> Tuple[bool, str]:
    """Check if exercise is practical (not obscure/weird)"""
    name_lower = exercise_name.lower()
    
    # Check for obscure patterns
    for pattern in OBSCURE_PATTERNS:
        if pattern in name_lower:
            return False, f"Obscure exercise with '{pattern}' - not practical"
    
    # HARD BLOCK: High-risk exercises that should never be auto-generated defaults
    blocked_patterns = [
        "good morning",  # High low-back injury risk
        "upright row",   # Shoulder impingement risk
        "behind neck",   # Shoulder injury risk
    ]
    for pattern in blocked_patterns:
        if pattern in name_lower:
            return False, f"Blocked pattern '{pattern}' - high injury risk"
    
    # BLOCK for beginners: Advanced exercises
    if user.experience_level == ExperienceLevel.BEGINNER:
        beginner_blocked = [
            "hanging pike", "hanging leg raise", "toes to bar",
            "split jump", "jump squat", "box jump",
            "muscle up", "planche", "handstand"
        ]
        for pattern in beginner_blocked:
            if pattern in name_lower:
                return False, f"Blocked for beginners: '{pattern}'"
    
    return True, "Practical exercise"

def calculate_exercise_score(exercise: Dict, user: UserProfile, 
                             target_muscles: List[str], already_selected: List[str]) -> float:
    """Calculate selection score for an exercise (higher = better)"""
    score = 100.0
    name = exercise.get('name', '')
    name_lower = name.lower()
    equipment = exercise.get('equipment', '')
    equip_lower = equipment.lower()
    
    # Get all muscles this exercise targets
    primary = exercise.get('primary_muscles', [])
    if isinstance(primary, str):
        primary = [primary]
    
    # Expanded target muscles
    expanded_targets = expand_target_muscles(target_muscles)
    
    # MUSCLE MATCH BONUS
    primary_lower = [m.lower() for m in primary if m]
    muscle_hits = 0
    for pm in primary_lower:
        for target in expanded_targets:
            if pm in target or target in pm:
                muscle_hits += 1
                break
    
    if muscle_hits > 0:
        score += 50 * muscle_hits
    else:
        score -= 100  # Heavy penalty for not hitting target
    
    # GYM EQUIPMENT PRIORITY (for gym users)
    # Machines should be prioritized for gym workouts - they're the hallmark of gym training!
    is_gym_user = user.workout_location == WorkoutLocation.GYM
    if is_gym_user:
        # Machines get TOP priority - "lever machine", "chest press machine", etc.
        if 'lever' in equip_lower or 'chest press machine' in equip_lower or 'leg press machine' in equip_lower:
            score += 120  # Highest boost for lever/plate-loaded machines
        elif 'machine' in equip_lower and 'cable' not in equip_lower:
            score += 110  # Other machines (smith, etc.)
        elif 'cable' in equip_lower:
            score += 100  # Cables are gym staples
        elif 'barbell' in equip_lower:
            score += 95   # Free weights are important but machines should lead
        elif 'dumbbell' in equip_lower:
            score += 85   # Dumbbells are versatile but can be done at home
    
    # WORKOUT CATEGORY MISMATCH PENALTIES
    # Shrugs don't belong on push days, squats don't belong on core days, etc.
    target_muscles_lower = [m.lower() for m in target_muscles]
    
    is_push_day = any('chest' in m or 'shoulder' in m or 'tricep' in m for m in target_muscles_lower) and \
                  not any('back' in m or 'bicep' in m or 'trap' in m for m in target_muscles_lower)
    is_core_day = any('core' in m or 'abs' in m or 'oblique' in m for m in target_muscles_lower) and \
                  len(target_muscles) <= 2
    
    # SHRUGS on Push Day = Wrong category
    if is_push_day and 'shrug' in name_lower:
        score -= 150  # Heavy penalty - shrugs don't belong on push days
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # BALANCE RULE - Boost shoulder-health moves on chest days, core on leg days
    # This keeps joints healthier without changing the user's chosen primary muscle
    # ═══════════════════════════════════════════════════════════════════════════════
    is_chest_day = any('chest' in m for m in target_muscles_lower)
    is_back_day = any('back' in m for m in target_muscles_lower)
    is_legs_day_check = any(t in m for m in target_muscles_lower for t in ['leg', 'quad', 'glute', 'hamstring'])
    
    # Chest day → boost face pulls / rear delt fly for shoulder balance
    if is_chest_day and not is_back_day:
        if 'face pull' in name_lower or 'rear delt' in name_lower or 'reverse fly' in name_lower:
            score += 80  # Shoulder-health balance move
    
    # Legs day → boost core stability moves
    if is_legs_day_check:
        if 'pallof' in name_lower or 'dead bug' in name_lower or 'plank' in name_lower:
            score += 60  # Core stability for legs
    
    # SQUATS/LEG PRESS on Core Day = Wrong category  
    if is_core_day and ('squat' in name_lower or 'leg press' in name_lower or 
                        'lunge' in name_lower or 'deadlift' in name_lower):
        score -= 200  # Heavy penalty - big lifts don't belong on core days
    
    # UPRIGHT ROWS - Shoulder irritation risk
    if 'upright row' in name_lower:
        score -= 80  # Moderate penalty - risky for shoulders
    
    # COMPOUND MOVEMENT BONUS
    compound_keywords = ['press', 'squat', 'deadlift', 'row', 'pull-up', 'pullup', 'dip', 'lunge', 'thrust']
    if any(kw in name_lower for kw in compound_keywords):
        score += 25
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # FOUNDATIONAL EXERCISE SCORING - Comprehensive system
    # When user has low workout count (<10), prioritize safe, repeatable exercises
    # ═══════════════════════════════════════════════════════════════════════════════
    
    # Determine if we should restrict to foundational exercises
    # Based on user's workout history and experience
    restrict_to_foundational = (
        user.workouts_completed < 10 or 
        user.experience_level == ExperienceLevel.BEGINNER
    )
    
    # Check using our new comprehensive lists
    is_foundational = is_foundational_exercise(name)
    is_risky = is_risky_exercise(name)
    
    # FOUNDATIONAL BOOST - Stronger when restricting
    if is_foundational:
        if restrict_to_foundational:
            score += 150  # Very strong boost for foundational when restricted
        elif user.experience_level == ExperienceLevel.BEGINNER:
            score += 100  # Strong boost for beginners
        else:
            score += 40   # Moderate boost for everyone else
    
    # RISKY EXERCISE PENALTY - Always apply, stronger when restricted
    if is_risky:
        if restrict_to_foundational:
            score -= 400  # BLOCK risky exercises for foundational mode
        else:
            score -= 150  # Still penalize risky exercises for advanced users
    
    # NON-FOUNDATIONAL PENALTY when restricted
    if restrict_to_foundational and not is_foundational:
        # Penalize exercises that aren't on the foundational list
        score -= 100  # Moderate penalty to prefer foundational
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # LOWER BACK SAFETY SCORING - Apply injury-based penalties
    # ═══════════════════════════════════════════════════════════════════════════════
    has_lower_back_issue = any(
        "lower back" in injury.area.lower() or "low back" in injury.area.lower() or "back" in injury.area.lower()
        for injury in user.injuries
    )
    
    if has_lower_back_issue:
        # Use our specialized functions
        if is_lower_back_stress_exercise(name):
            score -= 350  # Heavy penalty for back-stressing exercises
        
        if is_lower_back_safe_exercise(name):
            score += 100  # Boost safe alternatives
    
    # Apply general injury penalties
    injury_penalty = get_injury_exercise_penalties(name, user.injuries)
    score += injury_penalty  # This function returns negative values for penalties
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # LEGACY FOUNDATIONAL CHECK (keep for compatibility)
    # ═══════════════════════════════════════════════════════════════════════════════
    is_essential_foundational = any(found in name_lower for found in ESSENTIAL_FOUNDATIONAL)
    if is_essential_foundational:
        if user.experience_level == ExperienceLevel.BEGINNER:
            score += 50  # Additional boost for essential movements
        else:
            score += 20
    
    # VARIETY PENALTY - avoid similar exercises
    for selected in already_selected:
        # Check for same movement pattern
        movement_patterns = ["bench", "squat", "deadlift", "row", "press", "curl", "fly", "raise", "pulldown", "extension", "lunge"]
        for pattern in movement_patterns:
            if pattern in name_lower and pattern in selected.lower():
                score -= 50  # Penalty for similar movement
                break
    
    # OBSCURE EXERCISE PENALTY
    for pattern in OBSCURE_PATTERNS:
        if pattern in name_lower:
            score -= 200
    
    # ADVANCED EXERCISE PENALTY for beginners
    if user.experience_level == ExperienceLevel.BEGINNER:
        if any(adv in name_lower for adv in ADVANCED_EXERCISES):
            score -= 300
    
    # COMBO EXERCISE PENALTY - For ALL users (these are impractical for gym)
    # Exercises that combine two movements are complex and hard to progress
    combo_exercise_patterns = [
        "curl squat", "squat curl", "lunge curl", "curl lunge",
        "curtsey", "curtsy", "change lateral",  # Combo lunge patterns
        "deadlift to", "to row", "to curl", "to press",
        "renegade row", "and row", "and curl",
        "front raise", "squat front raise", "sumo squat front",  # Front raise combos
        "squat press", "press squat"  # Squat + press combos
    ]
    is_lunge_curl = "lunge" in name_lower and "curl" in name_lower
    is_squat_raise = "squat" in name_lower and "raise" in name_lower
    is_combo = any(p in name_lower for p in combo_exercise_patterns) or is_lunge_curl or is_squat_raise
    
    if is_combo:
        score -= 300  # VERY heavy penalty for ALL users - these are impractical
    
    # COMPLEX PLANK PENALTY - For ALL users (shoulder stability heavy)
    # Simple planks are fine, but plank+dumbbell variations are complex
    complex_plank_patterns = [
        "plank row", "plank raise", "plank lateral", "plank front",
        "plank with", "renegade", "commandos", "plank arm",
        "lateral raise plank", "raise plank"  # Catch variations with plank at end
    ]
    is_plank_combo = "plank" in name_lower and (
        "raise" in name_lower or "row" in name_lower or 
        "lateral" in name_lower or "dumbbell" in name_lower
    )
    
    if any(p in name_lower for p in complex_plank_patterns) or is_plank_combo:
        score -= 250  # Very strong penalty for complex planks (all users)
    
    # NICHE EXERCISE PENALTY - Prefer simple staples
    # "Reverse grip decline press" is niche; "Incline DB press" is a staple
    niche_patterns = [
        "reverse grip", "close grip", "wide grip",  # Grip variations
        "twisting", "rotating", "alternating",       # Complex movements
        "v-bar", "v bar", "sz bar", "ez bar",       # Unusual attachments
        "unilateral", "one arm", "single arm"        # Single-limb (harder to progress)
    ]
    niche_count = sum(1 for p in niche_patterns if p in name_lower)
    if niche_count > 0:
        score -= niche_count * 25  # Penalty per niche modifier
    
    # Exercises with very specific names are usually niche
    if "narrow stance" in name_lower or "wide stance" in name_lower or \
       "split stance" in name_lower or "staggered" in name_lower:
        score -= 20
    
    # BEGINNER COMPLEXITY PENALTY - mirrors Swift SmartExerciseSelectionEngine.swift
    # Combo moves, complex plank variations are too hard for beginners
    if user.experience_level == ExperienceLevel.BEGINNER:
        # COMBO EXERCISES: "Biceps Curl Squat", "Rear Lunge Biceps Curl", etc.
        combo_patterns = [
            "curl squat", "squat curl", "lunge curl", "curl lunge",
            "press squat", "squat press", "lunge press", "press lunge",
            "row lunge", "lunge row", "deadlift to", "to row", "to curl",
            "to press", "and curl", "and press", "and row", "renegade"
        ]
        # Also check for "lunge" + "curl" combo (like "Rear Lunge Biceps Curl")
        is_lunge_curl_combo = "lunge" in name_lower and "curl" in name_lower
        is_lunge_press_combo = "lunge" in name_lower and "press" in name_lower
        
        if any(pattern in name_lower for pattern in combo_patterns) or is_lunge_curl_combo or is_lunge_press_combo:
            score -= 200  # VERY heavy penalty - exclude combo moves for beginners
        
        # COMPLEX PLANK VARIATIONS: Plank with dumbbells, rows, raises
        complex_plank_patterns = [
            "plank row", "plank raise", "plank lateral", "plank front",
            "plank with", "renegade", "commandos", "plank arm"
        ]
        # Also check for "plank" combined with other movements
        is_plank_combo = "plank" in name_lower and (
            "raise" in name_lower or "row" in name_lower or 
            "lateral" in name_lower or "dumbbell" in name_lower
        )
        
        if any(pattern in name_lower for pattern in complex_plank_patterns) or is_plank_combo:
            score -= 200  # VERY heavy penalty for complex plank variations
        
        # TWISTING/ROTATING - too much coordination for beginners
        complex_movement_patterns = [
            "twisting", "rotating", "alternating", "switching",
            "curtsey", "curtsy", "change"  # "Change Lateral Raise Curtsey Lunge"
        ]
        if any(pattern in name_lower for pattern in complex_movement_patterns):
            score -= 150  # Heavy penalty for coordination-heavy movements
        
        # OVERLY COMPLEX NAMES (usually indicate complex movements)
        word_count = len(name.split())
        if word_count > 7:
            score -= 30  # Exercises with very long names are often complex
        
        # COMPLEX SQUAT VARIATIONS - Beginners need simple, loadable squat patterns
        # "Goblet Squat Side Shuffle" is hard to progress; "Goblet Squat" or "Leg Press" is better
        complex_squat_patterns = [
            "side shuffle", "shuffle", "lateral walk", "walk out",
            "jump", "pulse", "hold", "pause at bottom",
            "to press", "to curl", "to raise",  # Squat + other movement
            "twist", "rotation", "sumo to", "alternating"
        ]
        is_squat = "squat" in name_lower
        is_complex_squat = is_squat and any(p in name_lower for p in complex_squat_patterns)
        
        if is_complex_squat:
            score -= 250  # VERY heavy penalty - use simple squat or leg press instead
        
        # ═══════════════════════════════════════════════════════════════════════════════
        # BEGINNER-UNSAFE DEFAULTS - These should be "advanced options" not defaults
        # ═══════════════════════════════════════════════════════════════════════════════
        
        # HANGING EXERCISES - Too advanced for beginners
        if "hanging" in name_lower:
            score -= 200  # Hanging pikes, hanging leg raises too hard
        
        # GOOD MORNINGS - High injury risk for beginners
        if "good morning" in name_lower:
            score -= 200  # Too much low-back risk
        
        # PLYO/JUMP MOVEMENTS - Not appropriate as default for beginners
        plyo_patterns = [
            "jump", "hop", "bound", "plyo", "explosive", "power skip",
            "split jump", "box jump", "squat jump", "lunge jump"
        ]
        if any(p in name_lower for p in plyo_patterns):
            score -= 250  # Very high risk for beginners
        
        # DIPS as first exercise - Should be optional for beginners
        if "dip" in name_lower:
            score -= 80  # Deprioritize but don't fully block
        
        # SUPERMAN exercises - Low-back stress
        if "superman" in name_lower:
            score -= 150  # Too much low-back for beginners
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # ANCHOR QUALITY SCORING - Prefer exercises that are easy to load progressively
    # ═══════════════════════════════════════════════════════════════════════════════
    
    # HINGE ANCHOR PREFERENCE - Standard RDL/Romanian > Single-leg machine variants
    if "deadlift" in name_lower or "rdl" in name_lower or "romanian" in name_lower:
        # Prefer standard bilateral RDL/Romanian for anchors (easy to load)
        if "romanian" in name_lower or "rdl" in name_lower:
            if "single" not in name_lower and "one leg" not in name_lower and "alternate" not in name_lower:
                score += 40  # Boost bilateral RDL - great anchor
        
        # Demote single-leg variations for anchor purposes (harder to load progressively)
        if "single leg" in name_lower or "one leg" in name_lower or "alternate" in name_lower:
            score -= 30  # Good accessory, but not ideal anchor
        
        # Demote deadlifts "on" machines that aren't typical (hack squat machine deadlift)
        if "on hack" in name_lower or "on leg press" in name_lower:
            score -= 50  # Unusual setup, hard to standardize
    
    # Boost standard machine hinges that ARE good for loading
    if "lever" in name_lower and ("romanian" in name_lower or "hip hinge" in name_lower):
        if "single" not in name_lower:
            score += 30  # Good machine hinge option
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # ROW PREFERENCES - Chest-supported/seated rows > bent-over rows
    # Bent-over rows stress the low back which often limits before back is trained
    # ═══════════════════════════════════════════════════════════════════════════════
    is_row = " row" in name_lower or name_lower.startswith("row")
    
    if is_row:
        # BOOST: Chest-supported, seated, machine rows (low-back friendly)
        if "chest supported" in name_lower or "chest-supported" in name_lower or "lying" in name_lower:
            score += 80  # Best option - no low-back stress
        elif "seated" in name_lower and "cable" in equip_lower:
            score += 70  # Seated cable row - stable, easy to learn
        elif "lever" in name_lower or ("machine" in equip_lower and "cable" not in equip_lower):
            score += 60  # Machine rows - stable path
        elif "cable" in equip_lower:
            score += 50  # Cable rows - good tension
        
        # PENALIZE: Bent-over rows (low-back limiting)
        # Stronger penalty for beginners, lighter penalty for others
        if "bent over" in name_lower or "bent-over" in name_lower:
            if user.experience_level == ExperienceLevel.BEGINNER:
                score -= 100  # Heavy penalty for beginners
            else:
                score -= 40  # Lighter penalty for intermediate/advanced
        
        if "barbell" in equip_lower and "bent" in name_lower:
            score -= 40  # Barbell bent-over even harder to stabilize
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # STANDARD PULLDOWN BOOST - Prefer clear, simple pulldown variations
    # ═══════════════════════════════════════════════════════════════════════════════
    if "lat pulldown" in name_lower or "pulldown" in name_lower:
        # Boost simple pulldowns
        simple_pulldown_keywords = ["wide grip", "close grip", "neutral grip", "underhand", "overhand"]
        is_simple = any(kw in name_lower for kw in simple_pulldown_keywords) or \
                    name_lower.count(" ") <= 3  # Short names are usually simpler
        
        if is_simple and "combo" not in name_lower and " and " not in name_lower:
            score += 40  # Prefer standard pulldowns
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # UNSTABLE/COMPLEX PUSH-UP PENALTIES - Prefer stable pressing for hypertrophy
    # ═══════════════════════════════════════════════════════════════════════════════
    complex_pushup_patterns = [
        "bear crawl", "crawl push", "plank push", "push up to",
        "push-up to", "superman push", "archer", "clapping"
    ]
    if any(p in name_lower for p in complex_pushup_patterns):
        score -= 200  # Heavy penalty - use stable presses instead
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # COMPLEX/AMBIGUOUS EXERCISE PENALTIES - Prefer simple, clear movements
    # ═══════════════════════════════════════════════════════════════════════════════
    ambiguous_patterns = [
        "superman lift and", "lunge twist", "squat twist",
        "and lat pulldown", "to lat pulldown", "combo"
    ]
    if any(p in name_lower for p in ambiguous_patterns):
        score -= 250  # Heavy penalty - use clear, standard exercises
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # 21s PENALTY FOR BEGINNERS - Too complex, prefer standard curls
    # ═══════════════════════════════════════════════════════════════════════════════
    if "21s" in name_lower or "21's" in name_lower or "twenty one" in name_lower:
        if user.experience_level == ExperienceLevel.BEGINNER:
            score -= 150  # Too complex for beginners
        else:
            score -= 30  # Slightly less preferred even for intermediates
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # NICHE SHOULDER EXERCISE PENALTIES - Prefer standard presses + lateral raises
    # ═══════════════════════════════════════════════════════════════════════════════
    niche_shoulder_patterns = [
        "w press", "seated w", "y press", "y raise", "t press",
        "around the world", "bus driver", "plate raise"
    ]
    if any(p in name_lower for p in niche_shoulder_patterns):
        score -= 100  # Prefer standard overhead press + lateral raises
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # LATERAL RAISE BOOST - Important for shoulder development
    # ═══════════════════════════════════════════════════════════════════════════════
    if "lateral raise" in name_lower or "side raise" in name_lower:
        if "cable" in equip_lower or "dumbbell" in equip_lower:
            score += 60  # Great isolation for delts
        elif "machine" in equip_lower or "lever" in equip_lower:
            score += 40  # Machine lateral raise is fine too
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # TRICEPS VARIETY - Prefer pressdowns/overhead extensions over kickbacks
    # Kickbacks are fine but shouldn't dominate triceps selection
    # ═══════════════════════════════════════════════════════════════════════════════
    if "kickback" in name_lower:
        score -= 40  # Slight penalty to allow variety
    
    if "pushdown" in name_lower or "press down" in name_lower or "pressdown" in name_lower:
        score += 50  # Boost standard pressdowns
    
    if "overhead extension" in name_lower or "overhead tricep" in name_lower:
        score += 40  # Boost overhead extensions (long head)
    
    if "skull crusher" in name_lower or "lying extension" in name_lower:
        score += 30  # Good compound triceps work
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # SHRUG PENALTY ON PULL DAYS - When biceps is a target, prefer curls over shrugs
    # ═══════════════════════════════════════════════════════════════════════════════
    if "shrug" in name_lower:
        score -= 60  # Shrugs are traps-focused, often not the priority
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # UPRIGHT ROW PENALTY - Common shoulder irritator for ALL users
    # Prefer face pulls, rear delt fly instead
    # ═══════════════════════════════════════════════════════════════════════════════
    if "upright row" in name_lower or "upright pull" in name_lower or "lying upright" in name_lower:
        score -= 250  # VERY heavy penalty - shoulder impingement risk
    
    # HIGH PULL PENALTY - Similar shoulder stress
    if "high pull" in name_lower:
        score -= 120  # Deprioritize for general population
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # GOOD MORNING PENALTY FOR ALL USERS - High low-back risk
    # ═══════════════════════════════════════════════════════════════════════════════
    if "good morning" in name_lower:
        score -= 300  # BLOCK - High injury risk - prefer RDL or back extension
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # HANGING EXERCISES PENALTY - Advanced movements not for defaults
    # ═══════════════════════════════════════════════════════════════════════════════
    if "hanging" in name_lower:
        score -= 200  # Hanging pikes, leg raises too advanced as defaults
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # SPLIT JUMP / PLYO PENALTY FOR ALL USERS - Not appropriate as default
    # ═══════════════════════════════════════════════════════════════════════════════
    plyo_all_users = ["split jump", "jump squat", "box jump", "lunge jump", "squat jump"]
    if any(p in name_lower for p in plyo_all_users):
        score -= 280  # BLOCK - Prefer controlled step-ups, lunges
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # PLANK HOP/JUMP PENALTIES - Prefer calmer stability for health-focused users
    # ═══════════════════════════════════════════════════════════════════════════════
    if "plank hop" in name_lower or "plank jump" in name_lower or "mountain climber" in name_lower:
        if user.fitness_goal in [FitnessGoal.IMPROVE_HEALTH, FitnessGoal.STAY_ACTIVE]:
            score -= 100  # Too dynamic for health focus - prefer dead bugs, side planks
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # GOBLET SQUAT SIDE SHUFFLE PENALTY - Hard to load progressively
    # ═══════════════════════════════════════════════════════════════════════════════
    # Already covered by complex_squat_patterns above
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # INJURY-AWARE PENALTIES - Apply scoring penalties based on user injuries
    # This allows mild injuries to still get certain exercises but deprioritized
    # ═══════════════════════════════════════════════════════════════════════════════
    if user.injuries:
        injury_penalty = get_injury_exercise_penalties(name, user.injuries)
        score += injury_penalty
    
    return score

def generate_selection_reasoning(ex: Dict, user: UserProfile, target_muscles: List[str], 
                                   score_breakdown: Dict) -> str:
    """
    Generate detailed human-readable reasoning for why this exercise was selected.
    This mirrors our Swift codebase logic in SmartExerciseSelectionEngine.swift
    """
    name = ex.get('name', '')
    equipment = ex.get('equipment', '')
    primary = ex.get('primary_muscles', [])
    if isinstance(primary, str):
        primary = [primary]
    
    reasons = []
    
    # 1. MUSCLE TARGETING REASON
    muscle_str = ', '.join(primary) if primary else 'multiple muscles'
    reasons.append(f"✓ MUSCLE MATCH: Targets {muscle_str} which aligns with requested {', '.join(target_muscles)}")
    
    # 2. EQUIPMENT REASON
    equip_lower = equipment.lower()
    if 'lever' in equip_lower or 'machine' in equip_lower:
        if user.workout_location == WorkoutLocation.GYM:
            reasons.append(f"✓ GYM EQUIPMENT PRIORITY: Uses '{equipment}' - lever/machine exercises get +115-120 score boost for gym users per scoreGymEquipmentPriority()")
    elif 'cable' in equip_lower:
        if user.workout_location == WorkoutLocation.GYM:
            reasons.append(f"✓ CABLE EQUIPMENT: Uses Cable Machine - cables get +105 score boost for gym users (constant tension, isolation)")
    elif 'barbell' in equip_lower:
        reasons.append(f"✓ BARBELL: User has Barbell access - barbell exercises get +100 score boost for compounds")
    elif 'dumbbell' in equip_lower:
        reasons.append(f"✓ DUMBBELL: User has Dumbbell access - enables unilateral training (+85 gym score)")
    else:
        reasons.append(f"✓ EQUIPMENT MATCH: Uses '{equipment}' which user has available")
    
    # 3. EXPERIENCE LEVEL REASON  
    name_lower = name.lower()
    is_foundational = any(f in name_lower for f in ESSENTIAL_FOUNDATIONAL)
    if is_foundational:
        if user.experience_level == ExperienceLevel.BEGINNER:
            reasons.append(f"✓ FOUNDATIONAL BOOST: Recognized as core movement (+100 score for beginners via FoundationalExerciseDatabase)")
        else:
            reasons.append(f"✓ FOUNDATIONAL: Proven effective exercise (+30 score boost)")
    elif user.experience_level == ExperienceLevel.ADVANCED:
        reasons.append(f"✓ ADVANCED USER: User's experience ({user.workouts_completed} workouts) unlocks full exercise variety per ProgressiveUnlockSystem")
    
    # 4. COMPOUND VS ISOLATION
    compound_keywords = ['press', 'squat', 'deadlift', 'row', 'pull-up', 'pullup', 'dip', 'lunge', 'thrust']
    is_compound = any(kw in name_lower for kw in compound_keywords)
    if is_compound:
        reasons.append(f"✓ COMPOUND MOVEMENT: Multi-joint exercise gets +25 score boost (buildBalancedWorkout() targets 60% compounds)")
    else:
        reasons.append(f"✓ ISOLATION EXERCISE: Targets specific muscle group - important for balanced workout mix")
    
    # 5. INJURY SAFETY
    if user.injuries:
        injury_areas = [i.area.lower() for i in user.injuries]
        reasons.append(f"✓ INJURY SAFE: Passed LimitationsService.isExerciseSafe() check - does not stress {', '.join(injury_areas)}")
    else:
        reasons.append(f"✓ NO RESTRICTIONS: User has no injuries - full exercise pool available")
    
    # 6. GYM APPROPRIATENESS
    if user.workout_location == WorkoutLocation.GYM:
        if 'floor' not in name_lower and 'lying' not in name_lower:
            reasons.append(f"✓ GYM APPROPRIATE: Not a floor exercise - passes SmartDayGenerator gym user filter")
    
    # 7. VARIETY/DIVERSITY
    reasons.append(f"✓ VARIETY: Selected to ensure equipment diversity (max 50% same equipment type) and movement pattern variety")
    
    # 8. PRACTICALITY
    is_obscure = any(p in name_lower for p in OBSCURE_PATTERNS)
    if not is_obscure:
        reasons.append(f"✓ PRACTICAL: Common exercise that users can easily perform - passes practicalityFilter()")
    
    return " | ".join(reasons)

def get_exercise_count_for_duration(duration_minutes: int) -> int:
    """
    Get recommended exercise count based on workout duration.
    UPDATED: Duration cap rule - ≤40 min = 4-6 exercises max
    Rules:
    - 15-20 min: 4 exercises
    - 25-35 min: 5 exercises
    - 40 min: 6 exercises (cap for "quick" workouts)
    - 45-50 min: 7 exercises
    - 60+ min: 8 exercises (hard cap)
    """
    if duration_minutes <= 20:
        return 4
    elif duration_minutes <= 35:
        return 5
    elif duration_minutes <= 40:
        return 6  # Cap for "quick" workouts
    elif duration_minutes <= 50:
        return 7
    else:
        return 8  # Hard cap

def select_exercises_for_workout(exercises: List[Dict], user: UserProfile, 
                                  target_muscles: List[str], count: int = None) -> List[Dict]:
    """
    Main exercise selection function - mirrors Swift SmartExerciseSelectionEngine
    """
    # Determine exercise count based on duration if not specified
    if count is None:
        count = get_exercise_count_for_duration(user.preferred_workout_duration)
    
    print(f"\n{'='*60}")
    print(f"SELECTING EXERCISES FOR {user.name}")
    print(f"Target: {target_muscles}, Equipment: {user.available_equipment}")
    print(f"Experience: {user.experience_level.value}, Location: {user.workout_location.value}")
    print(f"Duration: {user.preferred_workout_duration} min -> {count} exercises")
    print(f"{'='*60}")
    
    is_gym_user = user.workout_location == WorkoutLocation.GYM
    expanded_targets = expand_target_muscles(target_muscles)
    
    # Phase 1: Filter exercises
    filtered = []
    filter_reasons = Counter()
    
    for ex in exercises:
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        primary = ex.get('primary_muscles', [])
        if isinstance(primary, str):
            primary = [primary]
        
        # Check muscle match
        primary_lower = [m.lower() for m in primary if m]
        muscle_match = any(
            target in muscle or muscle in target
            for muscle in primary_lower
            for target in expanded_targets
        )
        if not muscle_match:
            filter_reasons["muscle_mismatch"] += 1
            continue
        
        # Check equipment match
        equip_ok, equip_reason = check_equipment_match(equipment, user.available_equipment, is_gym_user)
        if not equip_ok:
            filter_reasons["equipment_mismatch"] += 1
            continue
        
        # Check gym appropriateness
        gym_ok, gym_reason = check_gym_appropriateness(name, equipment, is_gym_user)
        if not gym_ok:
            filter_reasons["gym_inappropriate"] += 1
            continue
        
        # Check injury safety
        safe, safety_reason = is_exercise_safe_for_injury(name, equipment, primary, user.injuries)
        if not safe:
            filter_reasons["injury_unsafe"] += 1
            continue
        
        # Check difficulty
        diff_ok, diff_reason = check_difficulty_appropriateness(name, user)
        if not diff_ok:
            filter_reasons["difficulty_inappropriate"] += 1
            continue
        
        # Check weight appropriateness
        weight_ok, weight_reason = check_weight_appropriateness(name, user)
        if not weight_ok:
            filter_reasons["weight_inappropriate"] += 1
            continue
        
        # Check practicality
        practical_ok, practical_reason = check_practicality(name, user)
        if not practical_ok:
            filter_reasons["impractical"] += 1
            continue
        
        # Skip stretching exercises
        workout_type = ex.get('workout_type', '').lower()
        if 'stretch' in workout_type or 'stretch' in name.lower():
            filter_reasons["stretching"] += 1
            continue
        
        # ═══════════════════════════════════════════════════════════════════════════════
        # FOUNDATIONAL MODE PRE-FILTER - Block risky exercises at filter stage
        # This is more efficient than penalizing them during scoring
        # ═══════════════════════════════════════════════════════════════════════════════
        restrict_to_foundational = (
            user.workouts_completed < 10 or 
            user.experience_level == ExperienceLevel.BEGINNER
        )
        
        if restrict_to_foundational:
            # Block risky exercises for foundational users
            if is_risky_exercise(name):
                filter_reasons["risky_for_foundational"] += 1
                continue
            
            # Block lower back stress exercises for users with back issues
            has_lower_back_issue = any(
                "lower back" in injury.area.lower() or "low back" in injury.area.lower() or "back" in injury.area.lower()
                for injury in user.injuries
            )
            if has_lower_back_issue and is_lower_back_stress_exercise(name):
                filter_reasons["lower_back_unsafe"] += 1
                continue
        
        filtered.append(ex)
    
    print(f"Filtered: {len(exercises)} -> {len(filtered)} exercises")
    print(f"Filter reasons: {dict(filter_reasons)}")
    
    if len(filtered) == 0:
        print("WARNING: No exercises passed filters!")
        return []
    
    # Phase 2: Score and select
    scored = []
    selected_names = []
    
    for ex in filtered:
        score = calculate_exercise_score(ex, user, target_muscles, selected_names)
        scored.append((score, ex))
    
    # Sort by score
    scored.sort(key=lambda x: -x[0])
    
    # Select with diversity constraints
    # MATCHES Swift SmartExerciseSelectionEngine.swift exactly
    selected = []
    used_equipment = Counter()
    exercise_families = Counter()  # Max 1 per family (Swift: maxPerExerciseFamily = 1)
    movement_patterns = Counter()  # Movement pattern limits from Swift MovementPattern enum
    
    # Movement pattern limits - Updated for better workout quality
    # From user feedback: max 1 hinge, max 2 rows (1 supported), don't stack overhead presses
    
    # Duration-based overhead press limit
    overhead_limit = 2 if user.preferred_workout_duration >= 45 else 1
    
    MOVEMENT_PATTERN_LIMITS = {
        "horizontal_press": 2,   # Bench press, push-ups
        "vertical_press": overhead_limit,  # Don't stack overhead presses unless 45+ min
        "horizontal_pull": 2,    # Rows (but we'll enforce 1 supported below)
        "vertical_pull": 2,      # Pull-ups, pulldowns
        "chest_fly": 1,          # Flyes, cable crossovers (isolation)
        "lateral_raise": 1,      # Side raises, front raises (isolation)
        "squat": 2,              # Squats, leg press
        "hinge": 1,              # Deadlifts, RDL - Max 1 per workout
        "back_extension": 1,     # Separate from hinge - only 1 per workout
        "lunge": 2,              # Lunges, split squats
        "leg_extension": 1,      # Leg extension (isolation)
        "leg_curl": 1,           # Leg curl (isolation)
        "bicep_curl": 1,         # Bicep curls (isolation)
        "tricep_extension": 1,   # Tricep pushdowns, extensions (isolation)
        "core_flexion": 2,       # Crunches, sit-ups
        "core_stability": 2,     # Planks, dead bugs
        "core_rotation": 1,      # Woodchops, Russian twists
        "rear_delt": 1,          # Rear delt fly, face pulls
        "other": 2,
    }
    
    # Track row types for "1 must be supported" rule
    unsupported_row_count = 0
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # WORKOUT TYPE DETECTION - Determine if this is a leg/lower body workout
    # ═══════════════════════════════════════════════════════════════════════════════
    target_lower = [t.lower() for t in target_muscles]
    is_legs_workout = any(t in target_lower for t in [
        "legs", "glutes", "quads", "hamstrings", "calves", "glute", "quad", "hamstring"
    ])
    is_upper_workout = any(t in target_lower for t in [
        "chest", "back", "shoulders", "biceps", "triceps", "arms"
    ]) and not is_legs_workout
    
    # Define upper body patterns to BLOCK on leg days
    UPPER_BODY_PATTERNS = {
        "horizontal_press", "vertical_press", "horizontal_pull", "vertical_pull",
        "chest_fly", "lateral_raise", "bicep_curl", "tricep_extension", "rear_delt", "shrug"
    }
    
    # Define lower body patterns
    LOWER_BODY_PATTERNS = {
        "squat", "hinge", "lunge", "leg_extension", "leg_curl", "hip_thrust", 
        "calf_raise", "back_extension", "leg_press"
    }
    
    # Max 1 exercise per family - MATCHES Swift maxPerExerciseFamily = 1
    MAX_PER_EXERCISE_FAMILY = 1
    
    for score, ex in scored:
        if len(selected) >= count:
            break
        
        name = ex.get('name', '')
        name_lower = name.lower()
        equipment = ex.get('equipment', '').lower()
        
        # Check for name uniqueness
        if name_lower in [s.get('name', '').lower() for s in selected]:
            continue
        
        # Check exercise family (prevent multiple bench press variations)
        # MATCHES Swift: maxPerExerciseFamily = 1
        family = detect_exercise_family(name)
        if family != "other" and exercise_families[family] >= MAX_PER_EXERCISE_FAMILY:
            continue
        
        # Check movement pattern limits - MATCHES Swift MovementPattern.maxPerWorkout
        movement_pattern = classify_movement_pattern(name, equipment)
        max_for_pattern = MOVEMENT_PATTERN_LIMITS.get(movement_pattern, 2)
        if movement_patterns[movement_pattern] >= max_for_pattern:
            continue
        
        # ═══════════════════════════════════════════════════════════════════════════════
        # CRITICAL: Block upper body exercises on leg/glute days
        # This prevents military press from appearing on leg workouts
        # ═══════════════════════════════════════════════════════════════════════════════
        if is_legs_workout and movement_pattern in UPPER_BODY_PATTERNS:
            continue  # Skip all upper body patterns on leg days
        
        # Also check for explicit upper body keywords on leg days
        if is_legs_workout:
            upper_body_keywords = [
                "press", "curl", "row", "pulldown", "pull-up", "pushdown",
                "fly", "raise", "tricep", "bicep", "shoulder", "chest", "lat"
            ]
            # Exception: leg press, leg curl are OK
            is_leg_specific = "leg" in name_lower or "ham" in name_lower or "quad" in name_lower
            has_upper_keyword = any(kw in name_lower for kw in upper_body_keywords)
            
            if has_upper_keyword and not is_leg_specific:
                continue  # Skip upper body exercises on leg days
        
        # ═══════════════════════════════════════════════════════════════════════════════
        # HINGE STACKING PREVENTION - Don't allow both deadlift AND back extension
        # ═══════════════════════════════════════════════════════════════════════════════
        is_back_extension = "back extension" in name_lower or "hyperextension" in name_lower or "hyper extension" in name_lower
        is_deadlift_pattern = "deadlift" in name_lower or "dead lift" in name_lower or "rdl" in name_lower or "romanian" in name_lower
        
        # Count existing hinges
        has_hinge = movement_patterns.get("hinge", 0) > 0
        has_back_ext = movement_patterns.get("back_extension", 0) > 0
        
        # If we already have a hinge (deadlift), don't allow back extension and vice versa
        if is_back_extension and has_hinge:
            continue
        if is_deadlift_pattern and has_back_ext:
            continue
        
        # ═══════════════════════════════════════════════════════════════════════════════
        # ROW SUPPORT RULE - If 2 rows, at least 1 must be supported (chest-supported/seated)
        # ═══════════════════════════════════════════════════════════════════════════════
        is_row = movement_pattern == "horizontal_pull"
        if is_row:
            is_supported_row = any(kw in name_lower for kw in [
                "chest supported", "chest-supported", "lying", "seated", "lever", "machine"
            ])
            
            # If we already have 1 unsupported row, this row MUST be supported
            if unsupported_row_count >= 1 and not is_supported_row:
                continue  # Skip this unsupported row
        
        # ═══════════════════════════════════════════════════════════════════════════════
        # EQUIPMENT DIVERSITY - MODIFIED for foundational mode
        # When foundational: LESS strict - allow repeating good equipment for progression
        # When advanced: NORMAL diversity enforcement
        # ═══════════════════════════════════════════════════════════════════════════════
        restrict_to_foundational = (
            user.workouts_completed < 10 or 
            user.experience_level == ExperienceLevel.BEGINNER
        )
        
        equip_category = categorize_equipment(equipment)
        
        if restrict_to_foundational:
            # FOUNDATIONAL MODE: Allow more same-equipment exercises for better progression
            # User feedback: "Equipment diversity is being gamed - using 6 different equipment
            # types for 6 exercises is not a win. For hypertrophy, you want repeatable, loadable staples."
            max_per_equipment = max(3, count // 2 + 1)  # More lenient - allow 3 of same equipment
            
            # Additionally, PRIORITIZE repeating proven equipment (barbell, machine)
            # Don't skip high-scoring exercises just because we've used the same equipment
            if score > 200 and equip_category in ['barbell', 'machine', 'cable']:
                max_per_equipment = count  # Don't limit top-scoring compound equipment
        else:
            # ADVANCED MODE: Normal diversity (max 50% same equipment)
            max_per_equipment = max(2, count // 2)
        
        if used_equipment[equip_category] >= max_per_equipment:
            continue
        
        # Generate selection reasoning BEFORE adding to selected
        reasoning = generate_selection_reasoning(ex, user, target_muscles, {"score": score})
        ex['selection_reasoning'] = reasoning
        ex['selection_score'] = score
        
        selected.append(ex)
        selected_names.append(name)
        exercise_families[family] += 1
        used_equipment[equip_category] += 1
        movement_patterns[movement_pattern] += 1
        
        # Track unsupported rows
        if movement_pattern == "horizontal_pull":
            is_supported = any(kw in name_lower for kw in [
                "chest supported", "chest-supported", "lying", "seated", "lever", "machine"
            ])
            if not is_supported:
                unsupported_row_count += 1
    
    print(f"Selected {len(selected)} exercises")
    for ex in selected:
        print(f"  - {ex.get('name')} [{ex.get('equipment')}]")
    
    return selected

def classify_movement_pattern(exercise_name: str, equipment: str) -> str:
    """
    Classify exercise into movement pattern for program generation.
    Updated to include all patterns needed for balanced programs.
    """
    name = exercise_name.lower()
    
    # === ARM ISOLATION (check first to catch specific patterns) ===
    
    # Bicep curls - any curl that's not leg curl
    if "curl" in name and "leg" not in name and "ham" not in name:
        return "bicep_curl"
    
    # Triceps work
    if "tricep" in name or "pushdown" in name or "press down" in name or \
       "skull crusher" in name or "skull press" in name or "french press" in name or \
       "overhead extension" in name or ("extension" in name and "tricep" in name):
        return "tricep_extension"
    
    # === SHOULDER ISOLATION ===
    
    # Lateral raises (side delts)
    if "lateral raise" in name or "side raise" in name or "side lateral" in name:
        return "lateral_raise"
    
    # Rear delt work
    if "rear delt" in name or "reverse fly" in name or "reverse flye" in name or \
       "face pull" in name or "rear fly" in name:
        return "rear_delt"
    
    # Front raises
    if "front raise" in name:
        return "front_raise"
    
    # === SHRUGS (check before presses due to name overlap) ===
    if "shrug" in name:
        return "shrug"
    
    # === PRESSING MOVEMENTS ===
    
    # Horizontal press (chest focus)
    if "bench press" in name or "push-up" in name or "pushup" in name or \
       "chest press" in name or "floor press" in name:
        return "horizontal_press"
    
    # Dips (can be chest or triceps)
    if "dip" in name:
        return "horizontal_press"
    
    # Vertical press (shoulder focus)
    if "overhead press" in name or "shoulder press" in name or "shoulders press" in name or \
       "military press" in name or "push press" in name or "arnold press" in name or \
       "viking press" in name or "pike" in name or "handstand" in name:
        return "vertical_press"
    
    # === PULLING MOVEMENTS ===
    
    # Vertical pull (lats) - CRITICAL for balanced program
    if "pull-up" in name or "pullup" in name or "chin-up" in name or \
       "chinup" in name or "pulldown" in name or "lat pull" in name or \
       "pull down" in name or "assisted pull" in name:
        return "vertical_pull"
    
    # Horizontal pull (rows) - include ALL row variations (narrow grip, wide grip, etc.)
    # CRITICAL: Check for " row" (with space) to avoid matching "narrow" in leg press names
    if (" row" in name or name.startswith("row") or "rowing" in name) and "upright" not in name:
        return "horizontal_pull"
    
    # Upright row (shoulder/trap work)
    if "upright row" in name:
        return "upright_row"
    
    # Shrugs
    if "shrug" in name:
        return "shrug"
    
    # === CHEST ISOLATION ===
    if "fly" in name or "flye" in name or "crossover" in name or "pec deck" in name:
        if "rear" not in name and "reverse" not in name:  # Not rear delt fly
            return "chest_fly"
    
    # === LEG MOVEMENTS ===
    
    # Leg curl (knee flexion hamstrings) - CRITICAL FIX
    if "leg curl" in name or "hamstring curl" in name or "lying curl" in name or \
       "seated curl" in name or "prone curl" in name:
        return "leg_curl"
    
    # Leg extension (quad isolation) - CRITICAL FIX
    if "leg extension" in name or "knee extension" in name:
        return "leg_extension"
    
    # Calf work
    if "calf" in name or "calf raise" in name or "calf press" in name or \
       "heel raise" in name or "gastrocnemius" in name or "soleus" in name:
        return "calf_raise"
    
    # Hip thrust specifically (separate from hinge)
    if "hip thrust" in name or "glute bridge" in name:
        return "hip_thrust"
    
    # Glute kickbacks
    if "kickback" in name and ("glute" in name or "donkey" in name):
        return "hip_thrust"  # Group with hip thrust for limiting
    
    # Glute press (machine)
    if "glute press" in name:
        return "hip_thrust"
    
    # Leg press (separate from squat for variety)
    if "leg press" in name:
        return "leg_press"
    
    # Back extension (separate from hinge to prevent stacking)
    if "hyperextension" in name or "back extension" in name or "hyper extension" in name:
        return "back_extension"
    
    # Hinge patterns (RDL, good morning, deadlift) - CHECK BEFORE SQUAT
    # This ensures "deadlift on hack squat machine" is classified as hinge
    if "deadlift" in name or "rdl" in name or "romanian" in name or "good morning" in name:
        return "hinge"
    
    # Squat patterns (after hinge check)
    if "squat" in name or "hack" in name:
        return "squat"
    
    # Lunge patterns
    if "lunge" in name or "split squat" in name or "step up" in name or "step-up" in name:
        return "lunge"
    
    # Hip abduction/adduction
    if "abduct" in name or "adduct" in name:
        return "hip_abduction"
    
    # === CORE (CRITICAL for fat loss programs) ===
    
    # Core flexion (crunches, sit-ups, leg raises)
    if "crunch" in name or "sit-up" in name or "situp" in name or \
       "leg raise" in name or "knee raise" in name or "toes to bar" in name:
        return "core_flexion"
    
    # Core stability (planks, Pallof press, dead bugs, hollow holds)
    if "plank" in name or "dead bug" in name or "hollow" in name or \
       "pallof" in name or "anti-rotation" in name or "bird dog" in name or \
       "stir the pot" in name or "ab wheel" in name or "rollout" in name:
        return "core_stability"
    
    # Core rotation (woodchops, twists, Russian twists)
    if "woodchop" in name or "wood chop" in name or "russian twist" in name or \
       ("rotation" in name and "core" in name):
        return "core_rotation"
    
    # Side planks and lateral core
    if "side plank" in name or "side bend" in name or "oblique" in name:
        return "core_lateral"
    
    return "other"


def detect_exercise_family(name: str) -> str:
    """
    Detect exercise family to prevent duplicates.
    MIRRORS Swift detectExerciseFamily() in SmartExerciseSelectionEngine.swift
    Max 1 exercise per family (maxPerExerciseFamily = 1)
    """
    name_lower = name.lower()
    
    # SPECIAL CASE: Combo exercises - classify by PRIMARY movement
    if "deadlift" in name_lower and ("row" in name_lower or "shrug" in name_lower):
        return "deadlift"
    if "deadlift" in name_lower and ("squat machine" in name_lower or "squat cage" in name_lower):
        return "deadlift"
    if "good morning" in name_lower:
        return "good_morning"
    if "back extension" in name_lower or "hyperextension" in name_lower:
        return "back_extension"
    
    # SHRUG - Check BEFORE bench press (equipment names can contain "bench")
    if "shrug" in name_lower and "deadlift" not in name_lower:
        return "shrug"
    
    # SKULL CRUSHER - Check early (contains "press" sometimes)
    if "skull" in name_lower or ("close grip" in name_lower and "skull" in name_lower):
        return "skull_crusher"
    
    # SMITH MACHINE PRESSES - Chest exercises on Smith
    if "smith" in name_lower and ("decline" in name_lower or "incline" in name_lower or "flat" in name_lower or "reverse grip" in name_lower):
        return "smith_chest_press"
    
    # CHEST FAMILIES
    if "bench press" in name_lower:
        return "bench_press"
    if "chest press" in name_lower:
        return "chest_press"
    # Incline/Decline/Flat Press variations without "bench" or "chest" in name
    if ("incline" in name_lower or "decline" in name_lower or "flat" in name_lower) and "press" in name_lower:
        # But not shoulder press
        if "shoulder" not in name_lower and "leg" not in name_lower:
            return "bench_press"
    if "fly" in name_lower or "flye" in name_lower:
        return "chest_fly"
    if "push-up" in name_lower or "pushup" in name_lower or "push up" in name_lower:
        return "pushup"
    if "crossover" in name_lower:
        return "cable_crossover"
    if "pec deck" in name_lower:
        return "pec_deck"
    
    # LEG FAMILIES
    if "leg press" in name_lower or ("sled" in name_lower and "press" in name_lower):
        return "leg_press"
    if "squat" in name_lower and "squat machine" not in name_lower and "squat cage" not in name_lower:
        return "squat"
    
    # DEADLIFT (check before row)
    if "deadlift" in name_lower:
        return "deadlift"
    
    # BACK FAMILIES - include all row variations (narrow grip, wide grip, etc.)
    # Note: "arrow" check was causing issues because "narrow" contains "arrow" - removed
    if "row" in name_lower and "upright" not in name_lower and "deadlift" not in name_lower:
        # Exclude "arrow" exercises but not "narrow" (which contains "arrow")
        if " arrow" in name_lower or name_lower.startswith("arrow"):
            pass  # Skip actual arrow exercises
        else:
            return "row"
    if "pulldown" in name_lower or "pull-down" in name_lower or "pull down" in name_lower:
        return "pulldown"
    if "pull-up" in name_lower or "pullup" in name_lower or "pull up" in name_lower:
        return "pullup"
    if "chin-up" in name_lower or "chinup" in name_lower or "chin up" in name_lower:
        return "chinup"
    if "face pull" in name_lower:
        return "face_pull"
    if "shrug" in name_lower and "deadlift" not in name_lower:
        return "shrug"
    if "lunge" in name_lower:
        return "lunge"
    if "leg extension" in name_lower:
        return "leg_extension"
    if "leg curl" in name_lower or "hamstring curl" in name_lower:
        return "leg_curl"
    if "calf raise" in name_lower or "calf press" in name_lower:
        return "calf_raise"
    if "hip thrust" in name_lower or "glute bridge" in name_lower:
        return "hip_thrust"
    if "step up" in name_lower or "step-up" in name_lower:
        return "step_up"
    
    # SHOULDER FAMILIES - MATCHES Swift exactly
    if "overhead press" in name_lower or "shoulder press" in name_lower or "shoulders press" in name_lower or \
       "military press" in name_lower or "arnold press" in name_lower or "behind neck press" in name_lower or \
       "front press" in name_lower or "neck press" in name_lower:
        return "shoulder_press"
    if "lateral raise" in name_lower or "side raise" in name_lower:
        return "lateral_raise"
    if "front raise" in name_lower:
        return "front_raise"
    if "rear delt" in name_lower or "reverse fly" in name_lower:
        return "rear_delt"
    if "upright row" in name_lower:
        return "upright_row"
    
    # ARM FAMILIES
    if "bicep curl" in name_lower or "biceps curl" in name_lower:
        return "bicep_curl"
    if "hammer curl" in name_lower:
        return "hammer_curl"
    if "preacher curl" in name_lower:
        return "preacher_curl"
    if "concentration curl" in name_lower:
        return "concentration_curl"
    if "tricep pushdown" in name_lower or "triceps pushdown" in name_lower:
        return "tricep_pushdown"
    if "tricep extension" in name_lower or "triceps extension" in name_lower:
        return "tricep_extension"
    if "skull crusher" in name_lower or "skullcrusher" in name_lower:
        return "skull_crusher"
    if "dip" in name_lower and "hip" not in name_lower:
        return "dip"
    if "kickback" in name_lower:
        return "kickback"
    
    # CORE FAMILIES - Prevent multiple plank/crunch variations
    if "plank" in name_lower:
        return "plank"
    if "crunch" in name_lower or "sit-up" in name_lower or "sit up" in name_lower:
        return "crunch"
    if "leg raise" in name_lower and "lateral" not in name_lower:
        return "leg_raise"
    if "pallof" in name_lower or "anti-rotation" in name_lower:
        return "anti_rotation"
    if "woodchop" in name_lower or "wood chop" in name_lower:
        return "woodchop"
    if "dead bug" in name_lower:
        return "dead_bug"
    if "hollow" in name_lower:
        return "hollow_hold"
    
    return "other"

def categorize_equipment(equipment: str) -> str:
    """Categorize equipment for diversity tracking"""
    equip_lower = equipment.lower()
    if 'barbell' in equip_lower:
        return 'barbell'
    elif 'dumbbell' in equip_lower:
        return 'dumbbell'
    elif 'cable' in equip_lower:
        return 'cable'
    elif 'machine' in equip_lower or 'lever' in equip_lower:
        return 'machine'
    elif 'kettlebell' in equip_lower:
        return 'kettlebell'
    elif 'band' in equip_lower or 'resistance' in equip_lower:
        return 'band'
    else:
        return 'bodyweight'

# ═══════════════════════════════════════════════════════════════════════════════
# WORKOUT ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════════

def analyze_exercise(exercise: Dict, user: UserProfile, target_muscles: List[str]) -> ExerciseAnalysis:
    """Perform critical analysis of a single exercise selection"""
    name = exercise.get('name', 'Unknown')
    equipment = exercise.get('equipment', 'Unknown')
    primary = exercise.get('primary_muscles', [])
    secondary = exercise.get('secondary_muscles', [])
    
    if isinstance(primary, str):
        primary = [primary]
    if isinstance(secondary, str):
        secondary = [secondary]
    
    issues = []
    is_gym_user = user.workout_location == WorkoutLocation.GYM
    
    # Check equipment validity
    equip_valid, equip_reason = check_equipment_match(equipment, user.available_equipment, is_gym_user)
    if not equip_valid:
        issues.append(f"EQUIPMENT: {equip_reason}")
    
    # Check muscle match
    expanded_targets = expand_target_muscles(target_muscles)
    primary_lower = [m.lower() for m in primary if m]
    muscle_match = any(
        target in muscle or muscle in target
        for muscle in primary_lower
        for target in expanded_targets
    )
    muscle_reason = "Matches target muscles" if muscle_match else f"Primary {primary} doesn't match targets {target_muscles}"
    if not muscle_match:
        issues.append(f"MUSCLE: {muscle_reason}")
    
    # Check difficulty
    diff_ok, diff_reason = check_difficulty_appropriateness(name, user)
    if not diff_ok:
        issues.append(f"DIFFICULTY: {diff_reason}")
    
    # Check injury safety
    safe, safety_reason = is_exercise_safe_for_injury(name, equipment, primary, user.injuries)
    if not safe:
        issues.append(f"SAFETY: {safety_reason}")
    
    # Check gym appropriateness
    gym_ok, gym_reason = check_gym_appropriateness(name, equipment, is_gym_user)
    if not gym_ok and is_gym_user:
        issues.append(f"GYM: {gym_reason}")
    
    # Check weight appropriateness
    weight_ok, weight_reason = check_weight_appropriateness(name, user)
    if not weight_ok:
        issues.append(f"WEIGHT: {weight_reason}")
    
    # Check practicality
    practical_ok, practical_reason = check_practicality(name, user)
    if not practical_ok:
        issues.append(f"PRACTICAL: {practical_reason}")
    
    # Get detailed selection reasoning (populated during selection phase)
    # This contains the WHY logic from our codebase's SmartExerciseSelectionEngine
    selection_reasoning = exercise.get('selection_reasoning', '')
    
    # If no detailed reasoning was captured, build basic reasoning
    if not selection_reasoning:
        reasoning_parts = []
        reasoning_parts.append(f"Equipment: {equip_reason}")
        reasoning_parts.append(f"Muscles: {muscle_reason}")
        reasoning_parts.append(f"Difficulty: {diff_reason}")
        reasoning_parts.append(f"Safety: {safety_reason}")
        if is_gym_user:
            reasoning_parts.append(f"Gym: {gym_reason}")
        reasoning_parts.append(f"Weight: {weight_reason}")
        reasoning_parts.append(f"Practicality: {practical_reason}")
        selection_reasoning = " | ".join(reasoning_parts)
    
    # Calculate score
    score = 100.0
    if not equip_valid:
        score -= 40
    if not muscle_match:
        score -= 30
    if not diff_ok:
        score -= 20
    if not safe:
        score -= 50
    if not gym_ok and is_gym_user:
        score -= 15
    if not weight_ok:
        score -= 25
    if not practical_ok:
        score -= 10
    
    is_approved = len(issues) == 0
    
    return ExerciseAnalysis(
        exercise_name=name,
        equipment=equipment,
        primary_muscles=primary,
        secondary_muscles=secondary,
        is_equipment_valid=equip_valid,
        equipment_reason=equip_reason,
        is_muscle_match=muscle_match,
        muscle_reason=muscle_reason,
        is_appropriate_difficulty=diff_ok,
        difficulty_reason=diff_reason,
        is_injury_safe=safe,
        injury_reason=safety_reason,
        is_practical=practical_ok and weight_ok,
        practical_reason=f"{practical_reason}; {weight_reason}",
        selection_score=max(0, score),
        selection_reasoning=selection_reasoning,
        issues=issues,
        is_approved=is_approved
    )

def analyze_workout(exercises: List[Dict], user: UserProfile, 
                   target_muscles: List[str], workout_num: int) -> WorkoutAnalysis:
    """Perform comprehensive analysis of a workout"""
    exercise_analyses = []
    critical_issues = []
    warnings = []
    recommendations = []
    
    # Analyze each exercise
    for ex in exercises:
        analysis = analyze_exercise(ex, user, target_muscles)
        exercise_analyses.append(analysis)
        
        if not analysis.is_approved:
            for issue in analysis.issues:
                if any(word in issue.upper() for word in ["SAFETY", "EQUIPMENT", "MUSCLE"]):
                    critical_issues.append(f"{analysis.exercise_name}: {issue}")
                else:
                    warnings.append(f"{analysis.exercise_name}: {issue}")
    
    # Calculate scores
    if not exercise_analyses:
        return WorkoutAnalysis(
            user_id=user.id,
            user_name=user.name,
            workout_number=workout_num,
            target_muscles=target_muscles,
            exercises=[],
            equipment_accuracy=0,
            muscle_accuracy=0,
            variety_score=0,
            difficulty_appropriateness=0,
            injury_safety_score=0,
            practicality_score=0,
            overall_score=0,
            grade="F",
            critical_issues=["No exercises generated"],
            warnings=[],
            recommendations=["Check filter logic - no exercises passed"]
        )
    
    n = len(exercise_analyses)
    equipment_accuracy = sum(1 for a in exercise_analyses if a.is_equipment_valid) / n * 100
    muscle_accuracy = sum(1 for a in exercise_analyses if a.is_muscle_match) / n * 100
    difficulty_score = sum(1 for a in exercise_analyses if a.is_appropriate_difficulty) / n * 100
    injury_safety = sum(1 for a in exercise_analyses if a.is_injury_safe) / n * 100
    practicality = sum(1 for a in exercise_analyses if a.is_practical) / n * 100
    
    # Variety score
    equipment_types = [a.equipment for a in exercise_analyses]
    unique_equipment = len(set(equipment_types))
    variety_score = min(100, (unique_equipment / n) * 100 + 20)
    
    # Check for exercise family duplicates
    families = [detect_exercise_family(a.exercise_name) for a in exercise_analyses]
    family_counts = Counter(families)
    max_family_count = max(family_counts.values()) if family_counts else 1
    if max_family_count > 1:
        duplicate_family = [f for f, c in family_counts.items() if c > 1 and f != "other"]
        if duplicate_family:
            warnings.append(f"Duplicate exercise families: {duplicate_family}")
            variety_score -= 20
    
    # Overall score (weighted)
    overall_score = (
        equipment_accuracy * 0.25 +
        muscle_accuracy * 0.25 +
        injury_safety * 0.25 +
        difficulty_score * 0.10 +
        practicality * 0.10 +
        variety_score * 0.05
    )
    
    # Grade
    if overall_score >= 95:
        grade = "A+"
    elif overall_score >= 90:
        grade = "A"
    elif overall_score >= 85:
        grade = "A-"
    elif overall_score >= 80:
        grade = "B+"
    elif overall_score >= 75:
        grade = "B"
    elif overall_score >= 70:
        grade = "B-"
    elif overall_score >= 65:
        grade = "C+"
    elif overall_score >= 60:
        grade = "C"
    elif overall_score >= 55:
        grade = "C-"
    elif overall_score >= 50:
        grade = "D"
    else:
        grade = "F"
    
    # Generate recommendations
    if equipment_accuracy < 100:
        recommendations.append("Fix equipment filtering - exercises with wrong equipment are being selected")
    if muscle_accuracy < 100:
        recommendations.append("Improve muscle targeting - some exercises don't hit target muscles")
    if injury_safety < 100:
        recommendations.append("CRITICAL: Injury filtering is failing - unsafe exercises are being selected")
    if variety_score < 70:
        recommendations.append("Improve variety - too many similar exercises or same equipment")
    
    return WorkoutAnalysis(
        user_id=user.id,
        user_name=user.name,
        workout_number=workout_num,
        target_muscles=target_muscles,
        exercises=exercise_analyses,
        equipment_accuracy=equipment_accuracy,
        muscle_accuracy=muscle_accuracy,
        variety_score=variety_score,
        difficulty_appropriateness=difficulty_score,
        injury_safety_score=injury_safety,
        practicality_score=practicality,
        overall_score=overall_score,
        grade=grade,
        critical_issues=critical_issues,
        warnings=warnings,
        recommendations=recommendations
    )

# ═══════════════════════════════════════════════════════════════════════════════
# PDF REPORT GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

def generate_pdf_report(all_analyses: List[WorkoutAnalysis], user_profiles: List[UserProfile], 
                       output_path: str, summary_stats: Dict):
    """Generate comprehensive PDF report"""
    doc = SimpleDocTemplate(output_path, pagesize=letter,
                           rightMargin=72, leftMargin=72,
                           topMargin=72, bottomMargin=72)
    
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        alignment=TA_CENTER,
        spaceAfter=30
    )
    
    heading_style = ParagraphStyle(
        'CustomHeading',
        parent=styles['Heading2'],
        fontSize=14,
        textColor=colors.darkblue,
        spaceAfter=12
    )
    
    subheading_style = ParagraphStyle(
        'CustomSubHeading',
        parent=styles['Heading3'],
        fontSize=12,
        textColor=colors.black,
        spaceAfter=6
    )
    
    normal_style = ParagraphStyle(
        'CustomNormal',
        parent=styles['Normal'],
        fontSize=10,
        spaceAfter=6
    )
    
    issue_style = ParagraphStyle(
        'Issue',
        parent=styles['Normal'],
        fontSize=9,
        textColor=colors.red,
        leftIndent=20
    )
    
    warning_style = ParagraphStyle(
        'Warning',
        parent=styles['Normal'],
        fontSize=9,
        textColor=colors.orange,
        leftIndent=20
    )
    
    success_style = ParagraphStyle(
        'Success',
        parent=styles['Normal'],
        fontSize=9,
        textColor=colors.green,
        leftIndent=20
    )
    
    story = []
    
    # Title page
    story.append(Paragraph("AUTO-GEN WORKOUT AUDIT REPORT", title_style))
    story.append(Paragraph(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", 
                          ParagraphStyle('Date', parent=styles['Normal'], alignment=TA_CENTER)))
    story.append(Spacer(1, 30))
    
    # Executive Summary
    story.append(Paragraph("EXECUTIVE SUMMARY", heading_style))
    
    summary_data = [
        ["Metric", "Value", "Status"],
        ["Total Users Tested", str(summary_stats['total_users']), ""],
        ["Total Workouts Generated", str(summary_stats['total_workouts']), ""],
        ["Total Exercises Analyzed", str(summary_stats['total_exercises']), ""],
        ["Average Score", f"{summary_stats['avg_score']:.1f}%", 
         "✅" if summary_stats['avg_score'] >= 80 else "⚠️" if summary_stats['avg_score'] >= 60 else "❌"],
        ["Equipment Accuracy", f"{summary_stats['avg_equipment']:.1f}%",
         "✅" if summary_stats['avg_equipment'] >= 95 else "⚠️" if summary_stats['avg_equipment'] >= 80 else "❌"],
        ["Muscle Accuracy", f"{summary_stats['avg_muscle']:.1f}%",
         "✅" if summary_stats['avg_muscle'] >= 95 else "⚠️" if summary_stats['avg_muscle'] >= 80 else "❌"],
        ["Injury Safety", f"{summary_stats['avg_safety']:.1f}%",
         "✅" if summary_stats['avg_safety'] >= 100 else "❌"],
        ["Critical Issues Found", str(summary_stats['critical_issues']),
         "✅" if summary_stats['critical_issues'] == 0 else "❌"],
    ]
    
    summary_table = Table(summary_data, colWidths=[200, 100, 50])
    summary_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.darkblue),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 10),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
        ('TEXTCOLOR', (0, 1), (-1, -1), colors.black),
        ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 1), (-1, -1), 9),
        ('GRID', (0, 0), (-1, -1), 1, colors.black),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ]))
    story.append(summary_table)
    story.append(Spacer(1, 20))
    
    # Grade Distribution
    story.append(Paragraph("GRADE DISTRIBUTION", heading_style))
    grades = Counter(a.grade for a in all_analyses)
    grade_data = [["Grade", "Count", "Percentage"]]
    for grade in ['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'F']:
        count = grades.get(grade, 0)
        pct = (count / len(all_analyses)) * 100 if all_analyses else 0
        grade_data.append([grade, str(count), f"{pct:.1f}%"])
    
    grade_table = Table(grade_data, colWidths=[80, 80, 80])
    grade_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('GRID', (0, 0), (-1, -1), 1, colors.black),
    ]))
    story.append(grade_table)
    
    story.append(PageBreak())
    
    # Critical Issues Summary
    if summary_stats['all_critical_issues']:
        story.append(Paragraph("CRITICAL ISSUES FOUND", heading_style))
        story.append(Paragraph("These issues MUST be fixed before production:", normal_style))
        
        for issue in summary_stats['all_critical_issues'][:20]:  # Top 20
            story.append(Paragraph(f"❌ {issue}", issue_style))
        
        if len(summary_stats['all_critical_issues']) > 20:
            story.append(Paragraph(f"... and {len(summary_stats['all_critical_issues']) - 20} more issues", normal_style))
        
        story.append(PageBreak())
    
    # Detailed User Reports
    story.append(Paragraph("DETAILED USER ANALYSIS", title_style))
    
    # Group analyses by user
    user_map = {u.id: u for u in user_profiles}
    analyses_by_user = defaultdict(list)
    for analysis in all_analyses:
        analyses_by_user[analysis.user_id].append(analysis)
    
    for user_id, user_analyses in analyses_by_user.items():
        user = user_map.get(user_id)
        if not user:
            continue
        
        # User Profile Header
        story.append(Paragraph(f"USER {user_id}: {user.name}", heading_style))
        
        # User details
        profile_text = f"""
        <b>Age:</b> {user.age} | <b>Gender:</b> {user.gender.value} | <b>Weight:</b> {user.weight_lbs} lbs | <b>Height:</b> {user.height_inches} in<br/>
        <b>Body Type:</b> {user.body_type.value} | <b>Experience:</b> {user.experience_level.value} | <b>Goal:</b> {user.fitness_goal.value}<br/>
        <b>Location:</b> {user.workout_location.value} | <b>Equipment:</b> {', '.join(user.available_equipment)}<br/>
        <b>Workouts Completed:</b> {user.workouts_completed} | <b>Preferred Duration:</b> {user.preferred_workout_duration} min<br/>
        """
        
        if user.injuries:
            injury_text = ", ".join([f"{i.area} ({i.severity})" for i in user.injuries])
            profile_text += f"<b>Injuries:</b> {injury_text}<br/>"
        
        profile_text += f"<b>Notes:</b> {user.notes}"
        
        story.append(Paragraph(profile_text, normal_style))
        story.append(Spacer(1, 10))
        
        # Each workout
        for analysis in user_analyses:
            story.append(Paragraph(
                f"Workout {analysis.workout_number}: {', '.join(analysis.target_muscles)} - Grade: {analysis.grade} ({analysis.overall_score:.1f}%)",
                subheading_style
            ))
            
            # Scores
            scores_text = f"""
            Equipment: {analysis.equipment_accuracy:.0f}% | Muscles: {analysis.muscle_accuracy:.0f}% | 
            Safety: {analysis.injury_safety_score:.0f}% | Variety: {analysis.variety_score:.0f}%
            """
            story.append(Paragraph(scores_text, normal_style))
            
            # Exercises (simple list - just names)
            for i, ex in enumerate(analysis.exercises, 1):
                status = "✅" if ex.is_approved else "❌"
                ex_text = f"{i}. {status} {ex.exercise_name} [{ex.equipment}]"
                style = success_style if ex.is_approved else issue_style
                story.append(Paragraph(ex_text, style))
            
            # Critical issues for this workout
            if analysis.critical_issues:
                story.append(Paragraph("Critical Issues:", 
                    ParagraphStyle('Bold', parent=normal_style, fontName='Helvetica-Bold', textColor=colors.red)))
                for issue in analysis.critical_issues:
                    story.append(Paragraph(f"• {issue}", issue_style))
            
            story.append(Spacer(1, 15))
        
        story.append(PageBreak())
    
    # Recommendations
    story.append(Paragraph("RECOMMENDATIONS FOR CODE FIXES", heading_style))
    
    all_recommendations = set()
    for analysis in all_analyses:
        all_recommendations.update(analysis.recommendations)
    
    for i, rec in enumerate(all_recommendations, 1):
        story.append(Paragraph(f"{i}. {rec}", normal_style))
    
    # Build PDF
    doc.build(story)
    print(f"📄 PDF Report saved to: {output_path}")

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    print("=" * 80)
    print("🏋️ COMPREHENSIVE AUTO-GEN WORKOUT AUDIT")
    print("=" * 80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Step 1: Load exercises from database
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
    
    # Step 2: Create test user profiles
    print("\n📋 Creating 20 diverse test user profiles...")
    user_profiles = create_test_user_profiles()
    print(f"✅ Created {len(user_profiles)} user profiles")
    
    for user in user_profiles:
        injury_str = f" (Injuries: {', '.join([i.area for i in user.injuries])})" if user.injuries else ""
        print(f"   {user.id}. {user.name} - {user.experience_level.value}, {user.workout_location.value}, Equipment: {user.available_equipment}{injury_str}")
    
    # Step 3: Generate workouts and analyze
    print("\n🏋️ Generating and analyzing workouts...")
    all_analyses = []
    all_critical_issues = []
    
    for user in user_profiles:
        print(f"\n{'='*60}")
        print(f"USER {user.id}: {user.name}")
        print(f"{'='*60}")
        
        # Generate 2 workouts per user with different muscle targets
        workout_splits_for_user = random.sample(WORKOUT_SPLITS, 2)
        
        for workout_num, split in enumerate(workout_splits_for_user, 1):
            target_muscles = split['muscles']
            
            print(f"\n--- Workout {workout_num}: {split['name']} ({', '.join(target_muscles)}) ---")
            
            # Select exercises using our logic
            selected_exercises = select_exercises_for_workout(
                all_exercises, user, target_muscles, count=6
            )
            
            # Analyze the workout
            analysis = analyze_workout(selected_exercises, user, target_muscles, workout_num)
            all_analyses.append(analysis)
            
            # Track critical issues
            all_critical_issues.extend(analysis.critical_issues)
            
            # Print summary
            print(f"\nWorkout Analysis:")
            print(f"  Grade: {analysis.grade} ({analysis.overall_score:.1f}%)")
            print(f"  Equipment Accuracy: {analysis.equipment_accuracy:.0f}%")
            print(f"  Muscle Accuracy: {analysis.muscle_accuracy:.0f}%")
            print(f"  Injury Safety: {analysis.injury_safety_score:.0f}%")
            
            if analysis.critical_issues:
                print(f"  ❌ CRITICAL ISSUES:")
                for issue in analysis.critical_issues:
                    print(f"     - {issue}")
    
    # Step 4: Calculate summary statistics
    print("\n" + "=" * 80)
    print("📊 AUDIT SUMMARY")
    print("=" * 80)
    
    total_exercises = sum(len(a.exercises) for a in all_analyses)
    
    summary_stats = {
        'total_users': len(user_profiles),
        'total_workouts': len(all_analyses),
        'total_exercises': total_exercises,
        'avg_score': sum(a.overall_score for a in all_analyses) / len(all_analyses) if all_analyses else 0,
        'avg_equipment': sum(a.equipment_accuracy for a in all_analyses) / len(all_analyses) if all_analyses else 0,
        'avg_muscle': sum(a.muscle_accuracy for a in all_analyses) / len(all_analyses) if all_analyses else 0,
        'avg_safety': sum(a.injury_safety_score for a in all_analyses) / len(all_analyses) if all_analyses else 0,
        'critical_issues': len(all_critical_issues),
        'all_critical_issues': all_critical_issues
    }
    
    print(f"\nTotal Users Tested: {summary_stats['total_users']}")
    print(f"Total Workouts Generated: {summary_stats['total_workouts']}")
    print(f"Total Exercises Analyzed: {summary_stats['total_exercises']}")
    print(f"\nAverage Scores:")
    print(f"  Overall: {summary_stats['avg_score']:.1f}%")
    print(f"  Equipment Accuracy: {summary_stats['avg_equipment']:.1f}%")
    print(f"  Muscle Accuracy: {summary_stats['avg_muscle']:.1f}%")
    print(f"  Injury Safety: {summary_stats['avg_safety']:.1f}%")
    print(f"\nCritical Issues Found: {summary_stats['critical_issues']}")
    
    # Grade distribution
    print("\nGrade Distribution:")
    grades = Counter(a.grade for a in all_analyses)
    for grade in ['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'F']:
        count = grades.get(grade, 0)
        pct = (count / len(all_analyses)) * 100 if all_analyses else 0
        bar = '█' * int(pct / 5)
        print(f"  {grade:3s}: {count:2d} ({pct:5.1f}%) {bar}")
    
    # Step 5: Generate PDF Report
    print("\n📄 Generating PDF Report...")
    output_path = "/Users/josephreed/Desktop/Workout App/Comprehensive_AutoGen_Audit_Report.pdf"
    generate_pdf_report(all_analyses, user_profiles, output_path, summary_stats)
    
    # Step 6: Save JSON results
    json_output = "/Users/josephreed/Desktop/Workout App/scripts/comprehensive_autogen_results.json"
    
    # Convert to serializable format
    results_data = {
        'summary': summary_stats,
        'user_profiles': [
            {
                'id': u.id,
                'name': u.name,
                'age': u.age,
                'gender': u.gender.value,
                'weight_lbs': u.weight_lbs,
                'experience': u.experience_level.value,
                'goal': u.fitness_goal.value,
                'location': u.workout_location.value,
                'equipment': u.available_equipment,
                'injuries': [{'area': i.area, 'severity': i.severity} for i in u.injuries],
                'notes': u.notes
            }
            for u in user_profiles
        ],
        'analyses': [
            {
                'user_id': a.user_id,
                'user_name': a.user_name,
                'workout_number': a.workout_number,
                'target_muscles': a.target_muscles,
                'grade': a.grade,
                'overall_score': a.overall_score,
                'equipment_accuracy': a.equipment_accuracy,
                'muscle_accuracy': a.muscle_accuracy,
                'injury_safety': a.injury_safety_score,
                'exercises': [
                    {
                        'name': e.exercise_name,
                        'equipment': e.equipment,
                        'primary_muscles': e.primary_muscles,
                        'is_approved': e.is_approved,
                        'issues': e.issues,
                        'reasoning': e.selection_reasoning
                    }
                    for e in a.exercises
                ],
                'critical_issues': a.critical_issues,
                'warnings': a.warnings,
                'recommendations': a.recommendations
            }
            for a in all_analyses
        ]
    }
    
    # Remove non-serializable items
    results_data['summary'] = {k: v for k, v in results_data['summary'].items() 
                               if k != 'all_critical_issues'}
    
    with open(json_output, 'w') as f:
        json.dump(results_data, f, indent=2)
    
    print(f"📁 JSON results saved to: {json_output}")
    
    # Final verdict
    print("\n" + "=" * 80)
    print("🎯 FINAL VERDICT")
    print("=" * 80)
    
    if summary_stats['avg_score'] >= 90 and summary_stats['critical_issues'] == 0:
        print("✅ AUTO-GEN SYSTEM PASSES AUDIT")
        print("   Ready for production deployment")
    elif summary_stats['avg_score'] >= 75 and summary_stats['critical_issues'] <= 5:
        print("⚠️ AUTO-GEN SYSTEM NEEDS MINOR FIXES")
        print("   Review critical issues before deployment")
    else:
        print("❌ AUTO-GEN SYSTEM REQUIRES SIGNIFICANT FIXES")
        print("   Do NOT deploy until issues are resolved")
    
    print("\n" + "=" * 80)

# ═══════════════════════════════════════════════════════════════════════════════
# 5-WEEK PROGRAM GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

class ProgramType(Enum):
    HYPERTROPHY = "Hypertrophy"      # Build Muscle
    STRENGTH = "Strength"            # Get Stronger
    FAT_LOSS = "Fat Loss"            # Lose Weight
    GENERAL_FITNESS = "General"      # Stay Active
    ENDURANCE = "Endurance"          # Build Endurance
    WELLNESS = "Wellness"            # Improve Health

class SplitType(Enum):
    FULL_BODY = "Full Body"
    UPPER_LOWER = "Upper/Lower"
    PUSH_PULL_LEGS = "Push/Pull/Legs"
    PUSH_PULL = "Push/Pull"

def get_program_type_from_goal(goal: FitnessGoal) -> ProgramType:
    """Map user goal to program type"""
    mapping = {
        FitnessGoal.BUILD_MUSCLE: ProgramType.HYPERTROPHY,
        FitnessGoal.GET_STRONGER: ProgramType.STRENGTH,
        FitnessGoal.LOSE_WEIGHT: ProgramType.FAT_LOSS,
        FitnessGoal.STAY_ACTIVE: ProgramType.GENERAL_FITNESS,
        FitnessGoal.BUILD_ENDURANCE: ProgramType.ENDURANCE,
        FitnessGoal.IMPROVE_HEALTH: ProgramType.WELLNESS,
    }
    return mapping.get(goal, ProgramType.GENERAL_FITNESS)

def get_recommended_split(days_per_week: int, experience: ExperienceLevel) -> SplitType:
    """Recommend split based on training frequency and experience"""
    if days_per_week <= 2:
        return SplitType.FULL_BODY
    elif days_per_week == 3:
        if experience == ExperienceLevel.BEGINNER:
            return SplitType.FULL_BODY
        else:
            return SplitType.PUSH_PULL_LEGS
    elif days_per_week == 4:
        return SplitType.UPPER_LOWER
    else:  # 5-7 days
        return SplitType.PUSH_PULL_LEGS

@dataclass
class DayRequirements:
    """Required movement patterns for a day to ensure complete muscle coverage"""
    name: str
    target_muscles: List[str]
    required_patterns: List[str]  # Movement patterns that MUST be included
    optional_patterns: List[str]  # Nice to have
    max_per_pattern: Dict[str, int]  # Limit redundancy

def get_day_template(split: SplitType, day_in_week: int, program_type: ProgramType) -> DayRequirements:
    """Get day name, target muscles, and REQUIRED movement patterns"""
    
    if split == SplitType.UPPER_LOWER:
        # Upper/Lower with A/B rotation for variety
        upper_day_num = day_in_week // 2  # 0, 1, 2, 3...
        
        if day_in_week % 2 == 0:  # Upper days
            if upper_day_num % 2 == 0:  # Upper A - Horizontal emphasis
                return DayRequirements(
                    name="Upper A - Horizontal Focus",
                    target_muscles=["Chest", "Back", "Shoulders", "Biceps", "Triceps"],
                    required_patterns=[
                        "horizontal_press",   # Bench press / chest press (main focus)
                        "horizontal_pull",    # Row (chest-supported preferred)
                        "vertical_pull",      # Pulldown / pull-up
                        "lateral_raise",      # Lateral delts
                        "bicep_curl",         # Direct arm work
                        "tricep_extension"    # Direct arm work
                    ],
                    optional_patterns=["chest_fly"],  # NO vertical_press on horizontal day - save for Upper B
                    # Block shoulder press on horizontal day - keeps pressing fresh for Upper B
                    max_per_pattern={"horizontal_pull": 1, "horizontal_press": 2, "vertical_press": 0, "hinge": 0}
                )
            else:  # Upper B - Vertical emphasis
                return DayRequirements(
                    name="Upper B - Vertical Focus",
                    target_muscles=["Chest", "Back", "Shoulders", "Biceps", "Triceps"],
                    required_patterns=[
                        "vertical_press",     # Overhead press
                        "vertical_pull",      # Pulldown / pull-up - CRITICAL
                        "horizontal_press",   # Incline or dips
                        "horizontal_pull",    # Seated cable row
                        "rear_delt",          # Rear delt fly / face pull
                        "bicep_curl",         # Direct arm work
                        "tricep_extension"    # Overhead triceps
                    ],
                    optional_patterns=["lateral_raise"],
                    max_per_pattern={"horizontal_pull": 1, "vertical_pull": 1, "hinge": 0}
                )
        else:  # Lower days
            lower_day_num = day_in_week // 2
            if lower_day_num % 2 == 0:  # Lower A - Quad emphasis
                return DayRequirements(
                    name="Lower A - Quad Focus",
                    target_muscles=["Quads", "Hamstrings", "Glutes", "Calves"],
                    required_patterns=[
                        "squat",              # FIRST: Hack squat / smith squat (true quad driver)
                        "leg_press",          # SECOND: Leg press variation
                        "leg_extension",      # Quad isolation
                        "leg_curl",           # Hamstring knee flexion
                        "calf_raise"          # Calves
                    ],
                    optional_patterns=[],  # NO optional - keep it focused on quads
                    # CRITICAL: NO hinge on quad day, NO upper body presses
                    max_per_pattern={"hinge": 0, "hip_thrust": 0, "vertical_press": 0, "horizontal_press": 0}
                )
            else:  # Lower B - Posterior emphasis
                return DayRequirements(
                    name="Lower B - Posterior Focus",
                    target_muscles=["Quads", "Hamstrings", "Glutes", "Calves"],
                    required_patterns=[
                        "hinge",              # ONLY ONE hinge (RDL as anchor - bilateral preferred)
                        "lunge",              # Split squat / lunge
                        "leg_curl",           # Lying/seated leg curl
                        "hip_thrust",         # ONE hip thrust variation
                        "calf_raise"          # Calves
                    ],
                    optional_patterns=["leg_extension"],  # Optional quad work
                    # CRITICAL: Only 1 hinge, NO squat (front squat is on Lower A), NO upper body presses
                    max_per_pattern={"hinge": 1, "hip_thrust": 1, "lunge": 1, "squat": 0, "leg_press": 0, "vertical_press": 0, "horizontal_press": 0}
                )
    
    elif split == SplitType.PUSH_PULL_LEGS:
        cycle = day_in_week % 3
        if cycle == 0:  # Push
            return DayRequirements(
                name="Push Day",
                target_muscles=["Chest", "Shoulders", "Triceps"],
                required_patterns=[
                    "horizontal_press",
                    "vertical_press",
                    "chest_fly",
                    "lateral_raise",
                    "tricep_extension"
                ],
                optional_patterns=["incline_press"],
                max_per_pattern={"horizontal_press": 2, "vertical_press": 1}
            )
        elif cycle == 1:  # Pull
            return DayRequirements(
                name="Pull Day",
                target_muscles=["Back", "Biceps", "Rear Delts"],
                required_patterns=[
                    "horizontal_pull",   # ONE row only (anchor)
                    "vertical_pull",     # ONE pulldown (anchor)  
                    "rear_delt",         # Rear delt fly / face pull (shoulder health)
                    "bicep_curl"
                ],
                optional_patterns=["shrug", "upper_back"],  # Light upper back work OK
                # STRICT LIMIT: Only 1 row + 1 pulldown - no row redundancy!
                max_per_pattern={"horizontal_pull": 1, "vertical_pull": 1, "hinge": 0, "row": 1}
            )
        else:  # Legs
            return DayRequirements(
                name="Leg Day",
                target_muscles=["Quads", "Hamstrings", "Glutes", "Calves"],
                required_patterns=[
                    "squat",
                    "hinge",
                    "leg_extension",
                    "leg_curl",
                    "calf_raise"
                ],
                optional_patterns=["hip_thrust", "lunge"],
                max_per_pattern={"hip_thrust": 1, "squat": 1, "hinge": 1}
            )
    
    elif split == SplitType.FULL_BODY:
        # Full Body with rotating emphasis for variety (A/B/C pattern)
        # Designed for BEGINNERS doing fat loss - simple, repeatable, recoverable
        day_type = day_in_week % 3
        
        if day_type == 0:  # Day A: Push emphasis + Legs + Core
            return DayRequirements(
                name="Full Body A - Push Focus",
                target_muscles=["Chest", "Back", "Shoulders", "Quads", "Core"],
                required_patterns=[
                    "horizontal_press",   # Chest press (anchor)
                    "vertical_pull",      # Pulldown (anchor)
                    "leg_press",          # Leg press - simple, loadable quad anchor (NOT complex squat)
                    "lateral_raise",      # Shoulder accessory
                    "core_stability"      # Plank/Pallof - ACTUAL core work
                ],
                optional_patterns=["tricep_extension"],
                # NO squat on Day A - use leg press instead (easier for beginners to progress)
                max_per_pattern={"horizontal_press": 1, "vertical_pull": 1, "leg_press": 1, "squat": 0, "hinge": 0}
            )
        elif day_type == 1:  # Day B: Pull emphasis + Hinge + Core
            return DayRequirements(
                name="Full Body B - Pull Focus",
                target_muscles=["Back", "Hamstrings", "Glutes", "Core", "Abs"],  # Include Abs for muscle matching
                required_patterns=[
                    "horizontal_pull",    # Row (anchor)
                    "vertical_pull",      # Pulldown
                    "hinge",              # RDL/Hinge (anchor) - ONLY lower body pattern this day
                    "leg_curl",           # Hamstring isolation
                    "core_flexion"        # Dead bug / crunch - ACTUAL core work
                ],
                optional_patterns=["bicep_curl"],
                # REDUCED leg volume: only 1 hinge, 1 leg curl, NO hip thrust/lunge/leg press
                max_per_pattern={"horizontal_pull": 1, "hinge": 1, "leg_curl": 1, "hip_thrust": 0, "lunge": 0, "leg_press": 0, "squat": 0}
            )
        else:  # Day C: Lower emphasis + Shoulders + Core
            return DayRequirements(
                name="Full Body C - Lower Focus",
                target_muscles=["Quads", "Glutes", "Hamstrings", "Shoulders", "Core"],
                required_patterns=[
                    "squat",              # Squat pattern (goblet/smith - simple anchor)
                    "lunge",              # UNILATERAL: Split squat/step-up/reverse lunge (1x/week)
                    "hip_thrust",         # Glute work
                    "lateral_raise",      # Shoulder work (instead of chest press - reduce repeat exposure)
                    "core_stability"      # Plank/Pallof - ACTUAL core work
                ],
                optional_patterns=["rear_delt", "calf_raise"],
                # Simple squat + lunge + hip thrust, NO chest press (already on Day A), NO leg press
                max_per_pattern={"squat": 1, "lunge": 1, "hip_thrust": 1, "horizontal_press": 0, "leg_press": 0, "hinge": 0}
            )
    
    # Default fallback
    return DayRequirements(
        name="Workout",
        target_muscles=["Full Body"],
        required_patterns=[],
        optional_patterns=[],
        max_per_pattern={}
    )

def get_program_name(goal: FitnessGoal, split: SplitType, experience: ExperienceLevel) -> str:
    """Generate a descriptive program name"""
    exp_prefix = {
        ExperienceLevel.BEGINNER: "Foundation",
        ExperienceLevel.INTERMEDIATE: "Progressive",
        ExperienceLevel.ADVANCED: "Advanced"
    }
    
    goal_name = {
        FitnessGoal.BUILD_MUSCLE: "Muscle Builder",
        FitnessGoal.GET_STRONGER: "Strength Program",
        FitnessGoal.LOSE_WEIGHT: "Fat Burner",
        FitnessGoal.STAY_ACTIVE: "Active Living",
        FitnessGoal.BUILD_ENDURANCE: "Endurance Builder",
        FitnessGoal.IMPROVE_HEALTH: "Wellness Program",
    }
    
    return f"{exp_prefix[experience]} {goal_name[goal]} ({split.value})"

def get_weekly_intensity(week_number: int, total_weeks: int = 5) -> str:
    """Progressive intensity across weeks - supports 5-week and 12-week programs"""
    
    if total_weeks == 5:
        # Original 5-week periodization
        if week_number == 1:
            return "Foundation Week - Focus on form, moderate intensity"
        elif week_number == 2:
            return "Building Week - Increasing volume"
        elif week_number == 3:
            return "Push Week - Higher intensity, challenging weights"
        elif week_number == 4:
            return "Peak Week - Maximum effort, test your limits"
        elif week_number == 5:
            return "Deload Week - Active recovery, reduced volume"
    
    elif total_weeks == 12:
        # 12-week periodization (3 mesocycles of 4 weeks each)
        # Block 1: Foundation (Weeks 1-4)
        if week_number == 1:
            return "Block 1 Week 1 - Foundation: Learn movements, moderate intensity"
        elif week_number == 2:
            return "Block 1 Week 2 - Foundation: Build volume, establish patterns"
        elif week_number == 3:
            return "Block 1 Week 3 - Foundation: Push intensity, refine technique"
        elif week_number == 4:
            return "Block 1 Week 4 - Deload: Active recovery before Block 2"
        # Block 2: Accumulation (Weeks 5-8)
        elif week_number == 5:
            return "Block 2 Week 1 - Accumulation: Increase volume, new variations"
        elif week_number == 6:
            return "Block 2 Week 2 - Accumulation: Build work capacity"
        elif week_number == 7:
            return "Block 2 Week 3 - Accumulation: Peak volume week"
        elif week_number == 8:
            return "Block 2 Week 4 - Deload: Recovery before intensity block"
        # Block 3: Intensification (Weeks 9-12)
        elif week_number == 9:
            return "Block 3 Week 1 - Intensification: Heavy weights, lower volume"
        elif week_number == 10:
            return "Block 3 Week 2 - Intensification: Push to new PRs"
        elif week_number == 11:
            return "Block 3 Week 3 - Peak: Test your limits, maximum effort"
        elif week_number == 12:
            return "Block 3 Week 4 - Final Deload: Celebrate progress, active recovery"
    
    elif total_weeks == 8:
        # 8-week periodization (2 mesocycles)
        if week_number <= 3:
            return f"Block 1 Week {week_number} - Foundation: Build base"
        elif week_number == 4:
            return "Block 1 Week 4 - Deload: Mid-program recovery"
        elif week_number <= 7:
            return f"Block 2 Week {week_number - 4} - Intensification: Push harder"
        else:
            return "Block 2 Week 4 - Final Deload: Program complete"
    
    return f"Week {week_number} - Training"

@dataclass
class ExercisePrescription:
    """Sets/reps/RIR for an exercise based on week and exercise type"""
    exercise: Dict
    sets: int
    reps: str  # e.g., "6-10" or "10-15"
    rir: int   # Reps in reserve
    rest: str  # e.g., "2-3 min" or "60-90 sec"
    is_anchor: bool  # True if this is an anchor lift (stays consistent)

def get_exercise_prescription(exercise: Dict, pattern: str, week: int, is_compound: bool, is_anchor: bool = False, total_weeks: int = 5) -> ExercisePrescription:
    """
    Get sets/reps/RIR prescription based on exercise type and week.
    Supports 5-week and 12-week programs with proper periodization.
    
    VOLUME RULES (prevents overkill):
    - Anchors: 3-4 sets (only anchors get 4 sets in build weeks)
    - Accessories: 2-3 sets (keep manageable for recovery)
    - Peak week: Only LAST SET of anchors goes to 0 RIR
    """
    # Determine if compound or isolation based on pattern
    compound_patterns = ["horizontal_press", "vertical_press", "horizontal_pull", "vertical_pull",
                        "squat", "leg_press", "hinge", "lunge", "hip_thrust"]
    is_compound = pattern in compound_patterns
    
    # Check for isolation glute work (kickbacks, etc.) - use higher reps
    # This MUST be checked BEFORE compound because hip_thrust pattern includes kickbacks
    exercise_name = exercise.get('name', '').lower()
    is_glute_isolation = any(p in exercise_name for p in ["kickback", "glute bridge", "fire hydrant", "clam", "donkey"])
    
    # Base prescription - GLUTE ISOLATION first (before compound check!)
    if is_glute_isolation:
        # Kickbacks, glute bridges, etc. - always isolation rep range
        base_sets = 2
        base_reps = "12-20"
        base_rest = "60-90 sec"
        is_compound = False  # Override - these are NOT compounds
    elif is_anchor:
        base_sets = 3
        base_reps = "6-10"
        base_rest = "2-3 min"
    elif is_compound:
        base_sets = 3
        base_reps = "6-10"
        base_rest = "2 min"
    else:
        base_sets = 2
        base_reps = "10-15"
        base_rest = "60-90 sec"
    
    # Determine phase based on week and total program length
    if total_weeks == 5:
        # Original 5-week periodization
        if week == 1:  # Foundation
            sets = base_sets
            rir = 3
            reps = base_reps
            rest = base_rest
        elif week == 2:  # Build
            sets = base_sets + 1 if is_anchor else base_sets
            rir = 2
            reps = base_reps
            rest = base_rest
        elif week == 3:  # Push
            sets = base_sets + 1 if is_anchor else min(base_sets, 3)
            rir = 1
            reps = base_reps
            rest = base_rest
        elif week == 4:  # Peak
            sets = base_sets + 1 if is_anchor else base_sets
            rir = 1  # Last set to 0 (marked with *)
            reps = "4-8" if is_compound else "8-12"
            rest = base_rest
        else:  # Week 5 - Deload
            sets = max(2, base_sets - 1)
            rir = 4
            reps = base_reps
            rest = "2 min" if is_compound else "60-90 sec"
    
    elif total_weeks == 12:
        # 12-week periodization (3 blocks of 4 weeks)
        block = (week - 1) // 4 + 1  # Block 1, 2, or 3
        week_in_block = (week - 1) % 4 + 1  # Week 1-4 within block
        
        is_deload = week_in_block == 4  # Every 4th week is deload
        is_peak = week == 11  # Week 11 is the peak
        
        if is_deload:
            # Deload weeks (4, 8, 12)
            sets = max(2, base_sets - 1)
            rir = 4
            reps = base_reps
            rest = "2 min" if is_compound else "60-90 sec"
        elif is_peak:
            # Peak week 11 - slightly dialed back for "stay active" goals (4-8 vs 3-6)
            sets = base_sets + 1 if is_anchor else base_sets
            rir = 1  # Last set to 0
            # Keep isolation at base reps (10-15 or 12-20), compounds go moderately heavy
            if is_glute_isolation:
                reps = base_reps  # Keep kickbacks at 12-20
                rest = "60-90 sec"  # Isolation rest
            elif is_compound:
                reps = "4-8"  # Slightly higher than 3-6 for joint/tendon safety
                rest = "2-3 min"
            else:
                reps = base_reps  # Keep isolation at 10-15
                rest = "60-90 sec"  # Isolation rest
        elif block == 1:
            # Block 1: Foundation (weeks 1-3)
            if week_in_block == 1:
                sets = base_sets
                rir = 3
            elif week_in_block == 2:
                # Week 2: Add set to anchors (matches progression table)
                sets = base_sets + 1 if is_anchor else base_sets
                rir = 2
            else:  # Week 3
                sets = base_sets + 1 if is_anchor else base_sets
                rir = 2
            reps = base_reps
            rest = base_rest
        elif block == 2:
            # Block 2: Accumulation (weeks 5-7) - higher volume
            sets = base_sets + 1 if is_anchor else base_sets
            if week_in_block == 1:
                rir = 2
            elif week_in_block == 2:
                rir = 2
            else:  # Week 7 - peak volume
                rir = 1
            reps = base_reps
            rest = base_rest
        else:
            # Block 3: Intensification (weeks 9-10) - heavier weights
            sets = base_sets + 1 if is_anchor else base_sets
            rir = 1
            # Keep isolation exercises at their base rep range (10-15 or 12-20)
            if is_glute_isolation:
                reps = base_reps  # Keep kickbacks at 12-20
                rest = "60-90 sec"  # Isolation rest - NOT long rest
            elif is_compound:
                reps = "4-8"
                rest = "2-3 min"
            else:
                reps = base_reps  # Keep isolation at 10-15
                rest = "60-90 sec"  # Isolation rest
    
    elif total_weeks == 8:
        # 8-week periodization (2 blocks of 4 weeks)
        is_deload = week == 4 or week == 8
        is_peak = week == 7
        
        if is_deload:
            sets = max(2, base_sets - 1)
            rir = 4
            reps = base_reps
            rest = "2 min" if is_compound else "60-90 sec"
        elif is_peak:
            sets = base_sets + 1 if is_anchor else base_sets
            rir = 1
            reps = "4-8" if is_compound else "8-12"
            rest = base_rest
        elif week <= 3:
            # Block 1: Foundation
            sets = base_sets + (1 if is_anchor and week >= 2 else 0)
            rir = 3 if week == 1 else 2
            reps = base_reps
            rest = base_rest
        else:
            # Block 2: Intensification
            sets = base_sets + 1 if is_anchor else base_sets
            rir = 2 if week == 5 else 1
            reps = base_reps
            rest = base_rest
    
    else:
        # Default: treat as simple progression
        sets = base_sets
        rir = 2
        reps = base_reps
        rest = base_rest
    
    return ExercisePrescription(
        exercise=exercise,
        sets=sets,
        reps=reps,
        rir=rir,
        rest=rest,
        is_anchor=is_anchor
    )

# =============================================================================
# CARDIO & CONDITIONING PRESCRIPTIONS (for Fat Loss / Endurance goals)
# =============================================================================

@dataclass
class CardioPrescription:
    """Cardio/conditioning prescription based on week and goal"""
    type: str           # "steady_state", "intervals", "finisher", "active_recovery"
    description: str    # User-friendly description
    duration: str       # e.g., "10-15 min", "8-10 rounds"
    intensity: str      # e.g., "Zone 2 (conversational)", "High Intensity"
    notes: str          # Additional guidance

@dataclass 
class ConditioningFinisher:
    """Quick conditioning circuit at the end of lifting"""
    name: str
    exercises: List[str]
    format: str         # e.g., "3 rounds", "AMRAP 5 min"
    notes: str

def get_cardio_prescription(week: int, total_weeks: int, goal: FitnessGoal, day_in_week: int) -> Optional[CardioPrescription]:
    """
    Get progressive cardio prescription based on week, goal, and day.
    
    FAT LOSS CARDIO PROGRESSION (applies to Lose Weight, Build Endurance):
    - Blocks progress in duration and intensity
    - Steady state on 2 days, optional intervals on 1 day
    - Deload weeks = active recovery only
    """
    
    # Only add cardio for fat loss / endurance goals
    if goal not in [FitnessGoal.LOSE_WEIGHT, FitnessGoal.BUILD_ENDURANCE]:
        return None
    
    # Determine if deload week
    if total_weeks == 5:
        is_deload = week == 5
        is_peak = week == 4
        block = 1 if week <= 2 else 2
    elif total_weeks == 8:
        is_deload = week in [4, 8]
        is_peak = week == 7
        block = 1 if week <= 4 else 2
    else:  # 12 weeks
        is_deload = week in [4, 8, 12]
        is_peak = week == 11
        if week <= 4:
            block = 1
        elif week <= 8:
            block = 2
        else:
            block = 3
    
    # Deload week = very light active recovery
    if is_deload:
        if day_in_week % 3 == 0:  # Only on first day of week
            return CardioPrescription(
                type="active_recovery",
                description="Light Walk or Easy Bike",
                duration="10-15 min",
                intensity="Very Easy (Zone 1)",
                notes="Just move! This is recovery, not training."
            )
        return None
    
    # Peak week = maintain but don't add fatigue
    if is_peak:
        if day_in_week % 3 == 0:
            return CardioPrescription(
                type="steady_state",
                description="Incline Walk or Light Bike",
                duration="12-15 min",
                intensity="Zone 2 (conversational pace)",
                notes="Keep it easy - save energy for peak lifting."
            )
        return None
    
    # Progressive cardio based on block
    day_type = day_in_week % 3
    
    if block == 1:
        # Foundation: Short, easy cardio to build habit
        if day_type == 0:  # Day A
            return CardioPrescription(
                type="steady_state",
                description="Incline Treadmill Walk",
                duration="10-12 min",
                intensity="Zone 2 (can hold conversation)",
                notes="3.0-3.5 mph, 5-8% incline. Build the habit."
            )
        elif day_type == 1:  # Day B
            return CardioPrescription(
                type="steady_state",
                description="Stationary Bike or Rowing",
                duration="10-12 min",
                intensity="Zone 2 (steady, sustainable)",
                notes="Focus on breathing rhythm, not speed."
            )
        else:  # Day C - optional
            return None
    
    elif block == 2:
        # Accumulation: Increase duration, add light intervals
        if day_type == 0:
            return CardioPrescription(
                type="steady_state",
                description="Incline Treadmill Walk",
                duration="15-18 min",
                intensity="Zone 2-3 (slightly challenging)",
                notes="3.5 mph, 8-10% incline. Push pace slightly."
            )
        elif day_type == 1:
            return CardioPrescription(
                type="steady_state",
                description="Stationary Bike or Rower",
                duration="15 min",
                intensity="Zone 2-3",
                notes="Increase resistance/pace from Block 1."
            )
        else:  # Day C - introduce intervals
            return CardioPrescription(
                type="intervals",
                description="Bike or Rower Intervals",
                duration="8-10 min total",
                intensity="30 sec hard / 90 sec easy x 5",
                notes="First time with intervals! Hard = can't talk, easy = recover."
            )
    
    else:  # Block 3
        # Intensification: Peak conditioning
        if day_type == 0:
            return CardioPrescription(
                type="steady_state",
                description="Incline Treadmill Walk/Jog",
                duration="18-20 min",
                intensity="Zone 3 (comfortably hard)",
                notes="Can walk fast or light jog. Push yourself."
            )
        elif day_type == 1:
            return CardioPrescription(
                type="intervals",
                description="Bike/Rower Intervals",
                duration="12-15 min total",
                intensity="30 sec sprint / 60 sec easy x 8-10",
                notes="This is your cardio peak week prep. Push hard on sprints."
            )
        else:  # Day C
            return CardioPrescription(
                type="steady_state",
                description="Your Choice: Walk/Bike/Rower",
                duration="15-20 min",
                intensity="Zone 2-3",
                notes="Pick what you enjoy. Consistency > perfection."
            )

def get_conditioning_finisher(week: int, total_weeks: int, goal: FitnessGoal, day_in_week: int, 
                              available_equipment: List[str]) -> Optional[ConditioningFinisher]:
    """
    Get a quick conditioning finisher for fat loss goals.
    These are SHORT circuits (3-5 min) at the end of lifting.
    
    ONLY for fat loss goals, and only on select days.
    """
    
    # Only for fat loss goal
    if goal != FitnessGoal.LOSE_WEIGHT:
        return None
    
    # Determine if deload
    if total_weeks == 5:
        is_deload = week == 5
    elif total_weeks == 8:
        is_deload = week in [4, 8]
    else:
        is_deload = week in [4, 8, 12]
    
    if is_deload:
        return None
    
    # Only on certain days (not every session)
    day_type = day_in_week % 3
    
    has_kettlebells = "Kettlebells" in available_equipment
    has_dumbbells = "Dumbbells" in available_equipment
    
    if day_type == 0 and week >= 2:  # Day A (Push Focus), starting week 2
        # NOTE: Day A already has leg press - avoid quad work in finisher (no goblet squats)
        if has_kettlebells:
            return ConditioningFinisher(
                name="Kettlebell Finisher",
                exercises=["KB Swings x 15", "KB Deadlifts x 10", "KB High Pull x 10"],
                format="2 rounds, minimal rest",
                notes="Use light-moderate weight. Focus on hip hinge, not squats (you already did leg press)."
            )
        elif has_dumbbells:
            return ConditioningFinisher(
                name="Dumbbell Finisher",
                exercises=["DB RDL x 12", "DB Row x 10", "DB Push Press x 8"],
                format="2 rounds, minimal rest",
                notes="Use light-moderate weight. Keep moving."
            )
    
    elif day_type == 2 and week >= 3:  # Day C, starting week 3
        return ConditioningFinisher(
            name="Bodyweight Burner",
            exercises=["Jumping Jacks x 20", "Bodyweight Squats x 15", "Mountain Climbers x 20"],
            format="2-3 rounds, 30 sec rest between rounds",
            notes="No equipment needed. Get your heart rate up!"
        )
    
    return None

@dataclass
class ProgramDay:
    week: int
    day_in_week: int
    day_number: int  # Overall day number in program
    name: str
    target_muscles: List[str]
    exercises: List[ExercisePrescription]  # Now includes sets/reps/RIR
    intensity: str
    notes: str
    cardio: Optional[CardioPrescription] = None  # Cardio prescription for fat loss
    finisher: Optional[ConditioningFinisher] = None  # Optional conditioning circuit

@dataclass
class GeneratedProgram:
    user: 'UserProfile'
    program_name: str
    program_type: ProgramType
    split_type: SplitType
    duration_weeks: int
    days_per_week: int
    total_days: int
    days: List[ProgramDay]

def select_exercises_for_program_day(
    exercises: List[Dict],
    day_requirements: DayRequirements,
    user: UserProfile,
    count: int,
    recently_used: Set[str],  # Exercises used in recent days (for non-anchors)
    week_number: int,
    anchor_lifts: Dict[str, Dict] = None  # Pattern -> exercise to keep consistent
) -> Tuple[List[Dict], Dict[str, Dict]]:
    """
    Select exercises for a program day ensuring REQUIRED movement patterns are fulfilled.
    Anchor lifts stay consistent across weeks for progressive overload tracking.
    Returns: (selected_exercises, updated_anchor_lifts)
    """
    target_muscles = day_requirements.target_muscles
    required_patterns = day_requirements.required_patterns
    max_per_pattern = day_requirements.max_per_pattern
    
    if anchor_lifts is None:
        anchor_lifts = {}
    
    print(f"\n{'='*60}")
    print(f"SELECTING EXERCISES FOR {user.name}: {day_requirements.name}")
    print(f"Target: {target_muscles}, Equipment: {user.available_equipment}")
    print(f"Required patterns: {required_patterns}")
    print(f"Experience: {user.experience_level.value}, Location: {user.workout_location.value}")
    print(f"Anchor lifts: {list(anchor_lifts.keys())}")
    print(f"{'='*60}")
    
    # Step 1: Filter exercises
    filter_reasons = {"equipment_mismatch": 0, "muscle_mismatch": 0, 
                      "stretching": 0, "injury_conflict": 0, "recently_used": 0}
    candidates = []
    
    # Get anchor exercise names (these bypass recently used filter)
    anchor_exercise_names = set()
    if anchor_lifts:
        for pattern, ex_dict in anchor_lifts.items():
            if isinstance(ex_dict, dict) and 'name' in ex_dict:
                anchor_exercise_names.add(ex_dict['name'])
    
    for ex in exercises:
        name = ex.get('name', 'Unknown')
        
        # Skip recently used exercises UNLESS it's an anchor (anchors repeat for progressive overload)
        if name in recently_used and name not in anchor_exercise_names:
            filter_reasons["recently_used"] += 1
            continue
        
        # Skip stretching exercises
        category = ex.get('category', '').lower()
        if 'stretch' in category:
            filter_reasons["stretching"] += 1
            continue
        
        # Check equipment match
        exercise_equipment = ex.get('equipment', '')
        is_gym = user.workout_location == WorkoutLocation.GYM
        matches, _ = check_equipment_match(exercise_equipment, user.available_equipment, is_gym)
        if not matches:
            filter_reasons["equipment_mismatch"] += 1
            continue
        
        # Check muscle match (PRIMARY MUSCLES MUST MATCH for program generation)
        primary = ex.get('primary_muscles', [])
        secondary = ex.get('secondary_muscles', [])
        if isinstance(primary, str):
            primary = [primary] if primary else []
        if isinstance(secondary, str):
            secondary = [secondary] if secondary else []
        
        # For muscle matching, use muscle group synonyms
        primary_lower = [m.lower().strip() for m in primary if m]
        target_lower = [t.lower().strip() for t in day_requirements.target_muscles]
        
        # Define muscle group synonyms for matching
        muscle_synonyms = {
            "back": ["back", "lats", "latissimus", "rhomboids", "traps", "trapezius", "upper back", "mid back"],
            "chest": ["chest", "pectorals", "pecs", "pectoral"],
            "shoulders": ["shoulders", "shoulder", "deltoids", "deltoid", "delts", "rear delt", "front delt", "side delt", "lateral delt"],
            "biceps": ["biceps", "bicep", "brachialis"],
            "triceps": ["triceps", "tricep"],
            "quads": ["quads", "quadriceps", "quad"],
            "hamstrings": ["hamstrings", "hamstring", "hams"],
            "glutes": ["glutes", "gluteus", "glute", "gluteal"],
            "calves": ["calves", "calf", "gastrocnemius", "soleus"],
        }
        
        # Expand target muscles with synonyms
        expanded_targets = set()
        for t in target_lower:
            expanded_targets.add(t)
            for group, synonyms in muscle_synonyms.items():
                if t in synonyms or any(t in s or s in t for s in synonyms):
                    expanded_targets.update(synonyms)
        
        # Define lower/upper body muscles for day type filtering
        lower_body_muscles = ["quads", "quadriceps", "hamstrings", "hamstring", "glutes", "gluteus", 
                              "calves", "calf", "legs", "leg", "hip", "hips", "adductors", "abductors"]
        upper_body_muscles = ["chest", "pectorals", "shoulders", "shoulder", "deltoids", "deltoid",
                              "biceps", "bicep", "triceps", "tricep", "back", "lats", "latissimus",
                              "traps", "trapezius", "rhomboids", "rear delt", "front delt", "side delt"]
        
        # Determine if this is a PURE lower body day (not Full Body)
        has_lower_body_targets = any(
            any(lb in t or t in lb for lb in lower_body_muscles)
            for t in target_lower
        )
        has_upper_body_targets = any(
            any(ub in t or t in ub for ub in upper_body_muscles)
            for t in target_lower
        )
        # Full Body has BOTH upper and lower targets - don't restrict
        is_pure_lower_body_day = has_lower_body_targets and not has_upper_body_targets
        
        # Check if exercise is upper body
        is_upper_body_exercise = any(
            any(ub in p or p in ub for ub in upper_body_muscles)
            for p in primary_lower
        )
        
        # STRICT: Filter out upper body exercises on PURE lower body days (not Full Body)
        if is_pure_lower_body_day and is_upper_body_exercise:
            filter_reasons["muscle_mismatch"] += 1
            continue
        
        # EXTRA STRICT: Block upper body pressing patterns on PURE lower days (prevents military press creeping in)
        if is_pure_lower_body_day:
            upper_press_patterns = ["shoulder press", "military press", "overhead press", 
                                    "bench press", "chest press", "incline press", "dip",
                                    "pushdown", "tricep", "bicep curl", "lateral raise"]
            if any(upp in name.lower() for upp in upper_press_patterns):
                filter_reasons["muscle_mismatch"] += 1
                continue
        
        # Also check exercise name for upper body indicators on PURE lower body days
        if is_pure_lower_body_day:
            upper_body_name_patterns = ["tricep", "bicep", "shoulder", 
                                        "chest", "fly", "lat ", "rear delt", "shrug"]
            # Be more careful with "curl", "press", "row", "pulldown" - they can be leg exercises
            # e.g., "Leg Curl", "Leg Press", "Prone Row" (for glutes)
            
            # More specific exclusions for leg day
            leg_exceptions = ["leg press", "leg curl", "leg extension", "hip", "glute", 
                              "calf", "squat", "lunge", "deadlift", "hamstring", "quad"]
            
            name_lower = name.lower()
            is_upper_in_name = any(p in name_lower for p in upper_body_name_patterns)
            is_leg_exception = any(e in name_lower for e in leg_exceptions)
            
            if is_upper_in_name and not is_leg_exception:
                filter_reasons["muscle_mismatch"] += 1
                continue
        
        # Check for muscle match using expanded synonyms
        primary_match = any(
            any(t in p or p in t for t in expanded_targets)
            for p in primary_lower
        )
        
        # If no primary muscles defined, try to match using exercise name
        if not primary_lower:
            name_lower = name.lower()
            # Infer muscle from name
            if is_pure_lower_body_day:
                primary_match = any(lb in name_lower for lb in lower_body_muscles) or \
                               any(p in name_lower for p in ["squat", "lunge", "deadlift", "hip thrust", "calf"])
            else:
                primary_match = True  # Allow if we can't determine
        
        if not primary_match:
            filter_reasons["muscle_mismatch"] += 1
            continue
        
        # Check injury conflicts
        if user.injuries:
            primary = ex.get('primary_muscles', [])
            if isinstance(primary, str):
                primary = [primary] if primary else []
            is_safe, _ = is_exercise_safe_for_injury(name, exercise_equipment, primary, user.injuries)
            if not is_safe:
                filter_reasons["injury_conflict"] += 1
                continue
        
        # Check gym appropriateness
        if is_gym:
            is_appropriate, _ = check_gym_appropriateness(name, exercise_equipment, user)
            if not is_appropriate:
                filter_reasons["equipment_mismatch"] += 1
                continue
        
        candidates.append(ex)
    
    print(f"Filtered: {len(exercises)} -> {len(candidates)} exercises")
    print(f"Filter reasons: {filter_reasons}")
    
    # Step 2: Score exercises and classify by movement pattern
    scored_by_pattern: Dict[str, List[Tuple[Dict, float]]] = {}
    all_scored = []
    
    for ex in candidates:
        score = calculate_exercise_score(ex, user, target_muscles, [])
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        pattern = classify_movement_pattern(name, equipment)
        
        if pattern not in scored_by_pattern:
            scored_by_pattern[pattern] = []
        scored_by_pattern[pattern].append((ex, score))
        all_scored.append((ex, score, pattern))
    
    # Sort each pattern's exercises by score
    for pattern in scored_by_pattern:
        scored_by_pattern[pattern].sort(key=lambda x: x[1], reverse=True)
    
    # Step 3: FIRST fill required patterns (ensures balanced program)
    selected = []
    selected_names = set()
    used_patterns = {}
    used_families = {}
    
    # Default pattern limits from day requirements or fallback
    default_pattern_limits = {
        "horizontal_press": 2, "vertical_press": 1,
        "horizontal_pull": 1, "vertical_pull": 1,  # Limit rows, ensure pulldowns
        "squat": 1, "leg_press": 1, "hinge": 1, "lunge": 1,
        "hip_thrust": 1,  # LIMIT hip thrust variations
        "leg_curl": 1, "leg_extension": 1, "calf_raise": 1,
        "chest_fly": 1, "lateral_raise": 1, "rear_delt": 1,
        "bicep_curl": 1, "tricep_extension": 1,
        "shrug": 1, "other": 2
    }
    
    # Merge with day-specific limits
    pattern_limits = {**default_pattern_limits, **max_per_pattern}
    
    # Define anchor patterns (these exercises stay consistent across weeks)
    anchor_patterns = ["horizontal_press", "horizontal_pull", "vertical_pull", "squat", "leg_press", "hinge"]
    
    print(f"Filling required patterns: {required_patterns}")
    
    # Fill REQUIRED patterns first
    for pattern in required_patterns:
        # Check if we have an anchor for this pattern from previous weeks
        if pattern in anchor_lifts and pattern in anchor_patterns:
            anchor_ex = anchor_lifts[pattern]
            name = anchor_ex.get('name', '')
            
            # Verify anchor is still in candidates
            if any(c.get('name') == name for c in candidates):
                selected.append(anchor_ex)
                selected_names.add(name)
                used_patterns[pattern] = used_patterns.get(pattern, 0) + 1
                print(f"  🔒 {pattern} (anchor): {name}")
                continue
        
        # Otherwise, pick best available
        if pattern in scored_by_pattern and scored_by_pattern[pattern]:
            for ex, score in scored_by_pattern[pattern]:
                name = ex.get('name', '')
                
                if name in selected_names:
                    continue
                
                # FILTER: Penalize complex/combo exercises
                name_lower = name.lower()
                complex_patterns = ["superman", "twist", "combo", " and ", " to ", "change", "curtsey"]
                if any(cp in name_lower for cp in complex_patterns):
                    continue  # Skip complex exercises entirely
                
                # Check family limits
                family = detect_exercise_family(name)
                if family:
                    if used_families.get(family, 0) >= 1:
                        continue
                    used_families[family] = used_families.get(family, 0) + 1
                
                # Check if pattern already filled
                if used_patterns.get(pattern, 0) >= pattern_limits.get(pattern, 1):
                    break
                
                selected.append(ex)
                selected_names.add(name)
                used_patterns[pattern] = used_patterns.get(pattern, 0) + 1
                
                # Store as anchor if this is an anchor pattern and Week 1
                if pattern in anchor_patterns and pattern not in anchor_lifts:
                    anchor_lifts[pattern] = ex
                    print(f"  ✓ {pattern} (NEW anchor): {name}")
                else:
                    print(f"  ✓ {pattern}: {name}")
                break
    
    # Check which required patterns were filled
    filled_required = [p for p in required_patterns if p in used_patterns]
    missing_required = [p for p in required_patterns if p not in used_patterns]
    
    if missing_required:
        print(f"  ⚠️ Missing patterns (no exercises found): {missing_required}")
    
    # Step 4: Fill remaining slots with best available (respecting limits)
    # Skip complex exercises and limit to reasonable count
    all_scored.sort(key=lambda x: x[1], reverse=True)
    
    for ex, score, pattern in all_scored:
        if len(selected) >= count:
            break
        
        name = ex.get('name', '')
        
        if name in selected_names:
            continue
        
        # Skip complex/combo exercises
        name_lower = name.lower()
        complex_patterns = ["superman", "twist", "combo", " and ", " to ", "change", "curtsey", "renegade"]
        if any(cp in name_lower for cp in complex_patterns):
            continue
        
        # Check pattern limit
        if used_patterns.get(pattern, 0) >= pattern_limits.get(pattern, 2):
            continue
        
        # Check family limit
        family = detect_exercise_family(name)
        if family and used_families.get(family, 0) >= 1:
            continue
        
        selected.append(ex)
        selected_names.add(name)
        used_patterns[pattern] = used_patterns.get(pattern, 0) + 1
        if family:
            used_families[family] = used_families.get(family, 0) + 1
    
    print(f"\nSelected {len(selected)} exercises:")
    for ex in selected:
        name = ex.get('name', '')
        pattern = classify_movement_pattern(name, ex.get('equipment', ''))
        is_anchor = pattern in anchor_lifts and anchor_lifts.get(pattern, {}).get('name') == name
        anchor_mark = " 🔒" if is_anchor else ""
        print(f"  - {name} [{pattern}]{anchor_mark}")
    
    print(f"Pattern coverage: {used_patterns}")
    
    return selected, anchor_lifts

def generate_program(user: UserProfile, exercises: List[Dict], duration_weeks: int = 5) -> GeneratedProgram:
    """Generate a complete program for a user with progressive variety.
    
    Supports:
    - 5 weeks (standard)
    - 8 weeks (intermediate)
    - 12 weeks (~90 days, advanced transformation)
    """
    
    # Determine program parameters
    program_type = get_program_type_from_goal(user.fitness_goal)
    split_type = get_recommended_split(user.available_days_per_week, user.experience_level)
    
    # Add duration to program name
    duration_suffix = {5: "", 8: "8-Week", 12: "12-Week"}
    base_name = get_program_name(user.fitness_goal, split_type, user.experience_level)
    program_name = f"{base_name} - {duration_suffix.get(duration_weeks, str(duration_weeks) + '-Week')}" if duration_weeks != 5 else base_name
    
    days_per_week = user.available_days_per_week
    total_days = duration_weeks * days_per_week
    
    print(f"\n{'='*70}")
    print(f"GENERATING {duration_weeks}-WEEK PROGRAM FOR: {user.name}")
    print(f"{'='*70}")
    print(f"Program: {program_name}")
    print(f"Goal: {user.fitness_goal.value}")
    print(f"Split: {split_type.value}")
    print(f"Days/Week: {days_per_week}")
    print(f"Total Training Days: {total_days}")
    print(f"Experience: {user.experience_level.value}")
    print(f"Equipment: {', '.join(user.available_equipment)}")
    if user.injuries:
        print(f"Injuries: {', '.join([f'{i.area} ({i.severity})' for i in user.injuries])}")
    
    program_days = []
    
    # Track anchor lifts by day template name (Upper A, Upper B, Lower A, Lower B)
    # These exercises stay consistent across weeks for progressive overload
    anchor_lifts_by_day: Dict[str, Dict[str, Dict]] = {}
    
    # Track non-anchor exercise variety
    day_type_history: Dict[str, List[Set[str]]] = {}
    
    for week in range(1, duration_weeks + 1):
        week_intensity = get_weekly_intensity(week, duration_weeks)
        print(f"\n{'='*60}")
        print(f"  WEEK {week}: {week_intensity}")
        print(f"{'='*60}")
        
        for day_in_week in range(days_per_week):
            day_number = (week - 1) * days_per_week + day_in_week + 1
            day_requirements = get_day_template(split_type, day_in_week, program_type)
            day_name = day_requirements.name
            
            # Initialize anchor tracking for this day type
            if day_name not in anchor_lifts_by_day:
                anchor_lifts_by_day[day_name] = {}
            
            # Determine day type for accessory variety tracking
            day_type = day_name.split()[0].lower()
            if day_type not in day_type_history:
                day_type_history[day_type] = []
            
            # For accessories, avoid recently used (but anchors stay)
            recently_used = set()
            for prev_exercises in day_type_history[day_type][-1:]:  # Only last session
                recently_used.update(prev_exercises)
            
            # Cap exercise count: 5-7 per session
            # Week 1/5: 5-6, Week 2-4: 6-7
            if week == 1:
                exercise_count = min(6, len(day_requirements.required_patterns))
            elif week == 5:  # Deload
                exercise_count = 5
            else:
                exercise_count = min(7, len(day_requirements.required_patterns) + 1)
            
            # Select exercises with anchor lift consistency
            selected, updated_anchors = select_exercises_for_program_day(
                exercises=exercises,
                day_requirements=day_requirements,
                user=user,
                count=exercise_count,
                recently_used=recently_used,
                week_number=week,
                anchor_lifts=anchor_lifts_by_day[day_name]
            )
            
            # Update anchors for this day type
            anchor_lifts_by_day[day_name] = updated_anchors
            
            # Order exercises based on day type (ensures proper emphasis)
            if "Quad Focus" in day_name:
                # QUAD DAY: Squat/leg press FIRST, then extension, then curls, then calves
                pattern_order = ["squat", "leg_press", "leg_extension", "leg_curl", "calf_raise", "hip_thrust", "lunge"]
            elif "Posterior Focus" in day_name:
                # POSTERIOR DAY: Hinge FIRST, then lunge, then curls, then hip thrust, then calves
                pattern_order = ["hinge", "lunge", "leg_curl", "hip_thrust", "calf_raise", "leg_extension"]
            elif "Horizontal" in day_name:
                # UPPER A: Horizontal press first, then row, then pulldown, then accessories
                pattern_order = ["horizontal_press", "horizontal_pull", "vertical_pull", "lateral_raise", "bicep_curl", "tricep_extension"]
            elif "Vertical" in day_name:
                # UPPER B: Back anchors first (pulldown/row), then pressing, then rear delts, then arms
                # This prioritizes back quality since pressing comes later when slightly fatigued
                pattern_order = ["vertical_pull", "horizontal_pull", "vertical_press", "horizontal_press", "rear_delt", "bicep_curl", "tricep_extension"]
            else:
                # Default: compounds first
                pattern_order = ["squat", "leg_press", "hinge", "horizontal_press", "vertical_press",
                                "horizontal_pull", "vertical_pull", "lunge"]
            
            def get_exercise_order(ex):
                pattern = classify_movement_pattern(ex.get('name', ''), ex.get('equipment', ''))
                if pattern in pattern_order:
                    return pattern_order.index(pattern)
                return 100  # Unlisted patterns last
            
            selected.sort(key=get_exercise_order)
            
            # Define compound patterns for prescription logic
            compound_patterns = ["horizontal_press", "vertical_press", "horizontal_pull", "vertical_pull",
                                "squat", "leg_press", "hinge", "lunge", "hip_thrust"]
            
            # Create exercise prescriptions with sets/reps/RIR
            exercise_prescriptions = []
            anchor_count = 0
            for ex in selected:
                ex_name = ex.get('name', '')
                pattern = classify_movement_pattern(ex_name, ex.get('equipment', ''))
                
                # Check if this exercise is an anchor for this pattern
                anchor_for_pattern = updated_anchors.get(pattern, {})
                anchor_name = anchor_for_pattern.get('name', '') if isinstance(anchor_for_pattern, dict) else ''
                is_anchor = pattern in updated_anchors and anchor_name == ex_name
                
                if is_anchor:
                    anchor_count += 1
                
                is_compound = pattern in compound_patterns
                
                prescription = get_exercise_prescription(ex, pattern, week, is_compound, is_anchor, duration_weeks)
                exercise_prescriptions.append(prescription)
            
            if week == 1:
                print(f"      → Anchors established: {anchor_count}")
            
            # Track which exercises were used for variety
            used_names = {ex.get('name', '') for ex in selected}
            day_type_history[day_type].append(used_names)
            
            # Get cardio prescription for fat loss / endurance goals
            cardio = get_cardio_prescription(week, duration_weeks, user.fitness_goal, day_in_week)
            
            # Get conditioning finisher for fat loss goals
            finisher = get_conditioning_finisher(week, duration_weeks, user.fitness_goal, day_in_week, user.available_equipment)
            
            program_days.append(ProgramDay(
                week=week,
                day_in_week=day_in_week + 1,
                day_number=day_number,
                name=day_name,
                target_muscles=day_requirements.target_muscles,
                exercises=exercise_prescriptions,
                intensity=week_intensity,
                notes=f"Week {week}, Day {day_in_week + 1}",
                cardio=cardio,
                finisher=finisher
            ))
            
            cardio_str = f" + Cardio" if cardio else ""
            finisher_str = f" + Finisher" if finisher else ""
            print(f"\n    ✓ Day {day_number}: {day_name} ({len(selected)} exercises{cardio_str}{finisher_str})")
    
    return GeneratedProgram(
        user=user,
        program_name=program_name,
        program_type=program_type,
        split_type=split_type,
        duration_weeks=duration_weeks,
        days_per_week=days_per_week,
        total_days=total_days,
        days=program_days
    )

def generate_program_pdf(program: GeneratedProgram, output_path: str):
    """Generate PDF report for the 5-week program"""
    
    doc = SimpleDocTemplate(output_path, pagesize=letter,
                           rightMargin=50, leftMargin=50,
                           topMargin=50, bottomMargin=50)
    
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'ProgramTitle',
        parent=styles['Heading1'],
        fontSize=22,
        alignment=TA_CENTER,
        spaceAfter=20,
        textColor=colors.darkblue
    )
    
    subtitle_style = ParagraphStyle(
        'Subtitle',
        parent=styles['Normal'],
        fontSize=12,
        alignment=TA_CENTER,
        spaceAfter=30,
        textColor=colors.grey
    )
    
    week_style = ParagraphStyle(
        'WeekHeader',
        parent=styles['Heading2'],
        fontSize=16,
        textColor=colors.darkgreen,
        spaceBefore=20,
        spaceAfter=10
    )
    
    day_style = ParagraphStyle(
        'DayHeader',
        parent=styles['Heading3'],
        fontSize=13,
        textColor=colors.darkblue,
        spaceBefore=12,
        spaceAfter=6
    )
    
    exercise_style = ParagraphStyle(
        'Exercise',
        parent=styles['Normal'],
        fontSize=10,
        leftIndent=20,
        spaceAfter=3
    )
    
    info_style = ParagraphStyle(
        'Info',
        parent=styles['Normal'],
        fontSize=10,
        spaceAfter=4
    )
    
    story = []
    
    # Title Page - Dynamic based on duration
    duration_title = f"{program.duration_weeks}-WEEK TRAINING PROGRAM"
    story.append(Paragraph(duration_title, title_style))
    story.append(Paragraph(program.program_name, subtitle_style))
    story.append(Spacer(1, 20))
    
    # User Profile Summary
    user = program.user
    story.append(Paragraph("ATHLETE PROFILE", styles['Heading2']))
    
    profile_data = [
        ["Name", user.name],
        ["Age", str(user.age)],
        ["Gender", user.gender.value],
        ["Weight", f"{user.weight_lbs} lbs"],
        ["Experience", user.experience_level.value],
        ["Goal", user.fitness_goal.value],
        ["Days/Week", str(program.days_per_week)],
        ["Equipment", ", ".join(user.available_equipment)],
    ]
    
    if user.injuries:
        profile_data.append(["Injuries", ", ".join([f"{i.area} ({i.severity})" for i in user.injuries])])
    
    profile_table = Table(profile_data, colWidths=[120, 300])
    profile_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.lightgrey),
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(profile_table)
    story.append(Spacer(1, 20))
    
    # Program Overview
    story.append(Paragraph("PROGRAM OVERVIEW", styles['Heading2']))
    overview_data = [
        ["Program Type", program.program_type.value],
        ["Training Split", program.split_type.value],
        ["Duration", f"{program.duration_weeks} Weeks"],
        ["Training Days", f"{program.days_per_week} days/week"],
        ["Total Sessions", str(program.total_days)],
    ]
    
    overview_table = Table(overview_data, colWidths=[120, 300])
    overview_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.lightblue),
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
    ]))
    story.append(overview_table)
    
    story.append(PageBreak())
    
    # Progression Guidelines - Dynamic based on program duration
    story.append(Paragraph("PROGRESSION GUIDELINES", styles['Heading2']))
    
    if program.duration_weeks == 12:
        # 12-Week progression table (3 blocks)
        progression_data = [
            ["Week", "Block", "Focus", "Anchor Sets", "RIR", "Notes"],
            ["1", "1", "Foundation", "3", "3", "Learn movements, moderate intensity"],
            ["2", "1", "Foundation", "4", "2", "Add set to anchors"],
            ["3", "1", "Foundation", "4", "2", "Push intensity, refine technique"],
            ["4", "1", "DELOAD", "2-3", "4", "Active recovery — NO FAILURE"],
            ["5", "2", "Accumulation", "4", "2", "Increase volume, new variations"],
            ["6", "2", "Accumulation", "4", "2", "Build work capacity"],
            ["7", "2", "Accumulation", "4", "1", "Peak volume week"],
            ["8", "2", "DELOAD", "2-3", "4", "Recovery — NO FAILURE"],
            ["9", "3", "Intensification", "4", "1", "Heavy weights, lower reps"],
            ["10", "3", "Intensification", "4", "1", "Push toward PRs"],
            ["11", "3", "Peak", "4", "1→0*", "Anchors 4-8 reps, last set @ RIR 0"],
            ["12", "3", "DELOAD", "2-3", "4", "Celebrate progress, recover"],
        ]
        prog_table = Table(progression_data, colWidths=[35, 35, 75, 55, 35, 180])
    elif program.duration_weeks == 8:
        # 8-Week progression table (2 blocks)
        progression_data = [
            ["Week", "Block", "Focus", "Anchor Sets", "RIR", "Notes"],
            ["1", "1", "Foundation", "3", "3", "Learn movements, moderate intensity"],
            ["2", "1", "Foundation", "4", "2", "Add set to anchors"],
            ["3", "1", "Foundation", "4", "2", "Push intensity"],
            ["4", "1", "DELOAD", "2-3", "4", "Mid-program recovery — NO FAILURE"],
            ["5", "2", "Intensification", "4", "2", "Push harder"],
            ["6", "2", "Intensification", "4", "1", "Increase load"],
            ["7", "2", "Peak", "4", "1→0*", "Sets 1-3 @ RIR 1, Set 4 @ RIR 0 (anchors only)"],
            ["8", "2", "DELOAD", "2-3", "4", "Final recovery — NO FAILURE"],
        ]
        prog_table = Table(progression_data, colWidths=[35, 35, 75, 55, 35, 180])
    else:
        # Default 5-Week progression table
        progression_data = [
            ["Week", "Focus", "Anchor Sets", "Accessory Sets", "RIR", "Notes"],
            ["1", "Foundation", "3", "2-3", "2-3", "Focus on form, moderate intensity"],
            ["2", "Build", "4", "2-3", "1-2", "Add set to anchors only"],
            ["3", "Push", "4", "3", "1", "Increase load, maintain quality"],
            ["4", "Peak", "4", "2-3", "1→0*", "Sets 1-3 @ RIR 1, Set 4 @ RIR 0 (anchors only)"],
            ["5", "Deload", "2-3", "2", "3-4", "Reduce volume 40-50%, easy effort"],
        ]
        prog_table = Table(progression_data, colWidths=[40, 70, 70, 70, 40, 150])
    
    prog_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.darkblue),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ]))
    story.append(prog_table)
    story.append(Spacer(1, 10))
    
    # Volume & Intensity Rules
    story.append(Paragraph("VOLUME RULES", styles['Heading3']))
    story.append(Paragraph("• <b>Anchors 🔒</b>: 3-4 sets — these are your primary overload drivers", info_style))
    story.append(Paragraph("• <b>Accessories</b>: 2-3 sets — support growth without crushing recovery", info_style))
    story.append(Paragraph("• <b>Peak Week</b>: Only the LAST set of anchors goes to 0 RIR, others stay at 1-2", info_style))
    story.append(Paragraph("• <b>Deload Weeks</b>: NO FAILURE — keep RIR ≥4, reduce volume, focus on recovery", info_style))
    story.append(Spacer(1, 8))
    
    # Rep Ranges
    story.append(Paragraph("REP RANGES", styles['Heading3']))
    story.append(Paragraph("• <b>Compounds</b> (Press, Row, Squat, Deadlift): 6-10 reps, 2-3 min rest", info_style))
    story.append(Paragraph("• <b>Isolation</b> (Curls, Extensions, Raises, Kickbacks): 10-15 reps, 60-90 sec rest", info_style))
    story.append(Paragraph("• 🔒 = Anchor lift (keep consistent for progressive overload)", info_style))
    
    # AUTOMATIC PROGRESSION RULE
    story.append(Spacer(1, 8))
    story.append(Paragraph("📈 HOW TO PROGRESS (Anchors)", styles['Heading3']))
    story.append(Paragraph("• When you hit the <b>top of the rep range</b> on all sets at the target RIR, <b>increase weight next week</b> (smallest jump available).", info_style))
    story.append(Paragraph("• If you miss the rep range, keep the same weight and try again next week.", info_style))
    story.append(Paragraph("• Example: Chest Press @ 50 lbs for 3x10 (hit all reps) → Next week: try 55 lbs for 3x6-10.", info_style))
    
    # Cardio Overview (for fat loss / endurance goals)
    if program.user.fitness_goal in [FitnessGoal.LOSE_WEIGHT, FitnessGoal.BUILD_ENDURANCE]:
        story.append(Spacer(1, 8))
        story.append(Paragraph("🏃 CARDIO PROGRESSION", styles['Heading3']))
        story.append(Paragraph("• <b>Block 1</b>: Foundation — 10-12 min steady state (Zone 2) after 2 sessions/week", info_style))
        story.append(Paragraph("• <b>Block 2</b>: Accumulation — 15-18 min steady state, introduce light intervals 1x/week", info_style))
        story.append(Paragraph("• <b>Block 3</b>: Intensification — 18-20 min, harder intervals + steady state options", info_style))
        story.append(Paragraph("• <b>Deload Weeks</b>: Light 10-15 min walk only — this is recovery, not training", info_style))
        story.append(Paragraph("• <b>Zone 2</b> = Conversational pace (can talk while moving)", info_style))
        
    # Conditioning Finishers (for fat loss goals)
    if program.user.fitness_goal == FitnessGoal.LOSE_WEIGHT:
        story.append(Spacer(1, 8))
        story.append(Paragraph("🔥 CONDITIONING FINISHERS", styles['Heading3']))
        story.append(Paragraph("• <b>Starting Week 2</b>: Short 2-3 round circuits after select workouts", info_style))
        story.append(Paragraph("• <b>Purpose</b>: Elevate heart rate, burn extra calories, build work capacity", info_style))
        story.append(Paragraph("• <b>Intensity</b>: Use light-moderate weights, focus on movement quality", info_style))
        story.append(Paragraph("• <b>Skip if</b>: Feeling overly fatigued or short on time — lifting is priority", info_style))
    
    # Injury Safeguard (if user has injuries)
    if program.user.injuries:
        story.append(Spacer(1, 8))
        story.append(Paragraph("⚠️ INJURY SAFEGUARDS", styles['Heading3']))
        for injury in program.user.injuries:
            if "knee" in injury.area.lower():
                story.append(Paragraph(f"• <b>{injury.area} ({injury.severity})</b>: If discomfort > 3/10, swap squats → leg press/hack squat; reduce ROM; keep RIR ≥2", info_style))
            elif "shoulder" in injury.area.lower():
                story.append(Paragraph(f"• <b>{injury.area} ({injury.severity})</b>: Avoid behind-neck pressing; limit overhead volume; use neutral grip when possible", info_style))
            elif "back" in injury.area.lower() or "spine" in injury.area.lower():
                story.append(Paragraph(f"• <b>{injury.area} ({injury.severity})</b>: Prioritize machine/supported exercises; avoid heavy spinal loading; brace properly", info_style))
            else:
                story.append(Paragraph(f"• <b>{injury.area} ({injury.severity})</b>: Modify exercises as needed; reduce ROM or load if discomfort > 3/10", info_style))
    
    story.append(PageBreak())
    
    # Weekly Breakdown
    current_week = 0
    for day in program.days:
        if day.week != current_week:
            current_week = day.week
            if current_week > 1:
                story.append(PageBreak())
            story.append(Paragraph(f"WEEK {current_week}", week_style))
            story.append(Paragraph(day.intensity, info_style))
            story.append(Spacer(1, 10))
        
        # Day header
        muscles_str = ", ".join(day.target_muscles)
        story.append(Paragraph(f"Day {day.day_in_week}: {day.name}", day_style))
        story.append(Paragraph(f"Target: {muscles_str}", info_style))
        
        # Determine if this is a peak week or deload week based on program duration
        is_deload_week = False
        is_peak_week = False
        
        if program.duration_weeks == 12:
            is_deload_week = day.week in [4, 8, 12]
            is_peak_week = day.week == 11
        elif program.duration_weeks == 8:
            is_deload_week = day.week in [4, 8]
            is_peak_week = day.week == 7
        else:  # 5 weeks
            is_deload_week = day.week == 5
            is_peak_week = day.week == 4
        
        # Exercise table with sets/reps/RIR
        exercise_data = [["#", "Exercise", "Sets", "Reps", "RIR", "Rest"]]
        
        for i, prescription in enumerate(day.exercises, 1):
            ex = prescription.exercise
            ex_name = ex.get('name', 'Unknown')
            anchor_mark = " 🔒" if prescription.is_anchor else ""
            
            # RIR display logic
            if is_deload_week:
                # DELOAD: Always RIR 4, NO failure notation
                rir_display = "4"
            elif is_peak_week and prescription.is_anchor:
                # PEAK: Clear "sets 1-3 @ RIR 1, set 4 @ RIR 0" for anchors
                rir_display = "1→0*"  # Indicates last set to failure
            else:
                rir_display = str(prescription.rir)
            
            exercise_data.append([
                str(i),
                f"{ex_name}{anchor_mark}",
                str(prescription.sets),
                prescription.reps,
                rir_display,
                prescription.rest
            ])
        
        ex_table = Table(exercise_data, colWidths=[20, 200, 35, 45, 35, 60])
        ex_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.lightblue),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, -1), 9),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
            ('ALIGN', (0, 0), (0, -1), 'CENTER'),
            ('ALIGN', (2, 0), (-1, -1), 'CENTER'),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
            ('LEFTPADDING', (0, 0), (-1, -1), 4),
            ('RIGHTPADDING', (0, 0), (-1, -1), 4),
        ]))
        story.append(ex_table)
        
        # Add Peak Week clarity note
        if is_peak_week:
            story.append(Spacer(1, 5))
            peak_box_style = ParagraphStyle('PeakBox', parent=styles['Normal'], 
                                           fontSize=8, backColor=colors.lightgreen,
                                           borderColor=colors.green, borderWidth=1,
                                           borderPadding=5)
            
            # Beginner-specific peak week guardrail
            if program.user.experience_level == ExperienceLevel.BEGINNER:
                peak_text = """<b>🎯 PEAK WEEK RULE (Beginner):</b> Only the <b>LAST SET</b> of anchor lifts (🔒) goes to 0 RIR (optional). Sets 1-3 stay at RIR 1-2. Accessories never go to failure.<br/>
                <b>⚠️ SAFETY:</b> If form breaks down OR you feel overly fatigued, <b>keep it at RIR 1</b> (no true failure). Progress > ego."""
            else:
                peak_text = """<b>🎯 PEAK WEEK RULE:</b> Only the <b>LAST SET</b> of anchor lifts (🔒) goes to 0 RIR (optional). Sets 1-3 stay at RIR 1-2. Accessories never go to failure."""
            
            story.append(Paragraph(peak_text, peak_box_style))
        
        # Add knee safeguard swap box for leg days if user has knee injury
        is_leg_day = any(m.lower() in ['quads', 'hamstrings', 'glutes', 'calves', 'legs'] 
                        for m in day.target_muscles)
        has_knee_injury = any('knee' in i.area.lower() for i in program.user.injuries) if program.user.injuries else False
        
        if is_leg_day and has_knee_injury:
            story.append(Spacer(1, 5))
            knee_box_style = ParagraphStyle('KneeBox', parent=styles['Normal'], 
                                           fontSize=8, backColor=colors.lightyellow,
                                           borderColor=colors.orange, borderWidth=1,
                                           borderPadding=5)
            knee_text = """<b>⚠️ KNEE SAFEGUARD SWAPS:</b><br/>
            • Front Squat → Hack Squat / Leg Press (controlled ROM)<br/>
            • Painful knee-dominant move → Swap to glute/hamstring pattern<br/>
            • Pain >3/10 → Keep RIR ≥2 (even in peak week, skip 0 RIR on lower anchors)"""
            story.append(Paragraph(knee_text, knee_box_style))
        
        # Add conditioning finisher (for fat loss goals)
        if day.finisher:
            story.append(Spacer(1, 5))
            finisher_box_style = ParagraphStyle('FinisherBox', parent=styles['Normal'], 
                                               fontSize=9, backColor=colors.HexColor('#FFE4E1'),  # Misty rose
                                               borderColor=colors.HexColor('#CD5C5C'),
                                               borderWidth=1, borderPadding=5)
            finisher_exercises = " → ".join(day.finisher.exercises)
            finisher_text = f"""<b>🔥 FINISHER: {day.finisher.name}</b><br/>
            {finisher_exercises}<br/>
            <i>Format: {day.finisher.format}</i><br/>
            <i>{day.finisher.notes}</i>"""
            story.append(Paragraph(finisher_text, finisher_box_style))
        
        # Add cardio prescription (for fat loss / endurance goals)
        if day.cardio:
            story.append(Spacer(1, 5))
            cardio_box_style = ParagraphStyle('CardioBox', parent=styles['Normal'], 
                                             fontSize=9, backColor=colors.HexColor('#E0FFFF'),  # Light cyan
                                             borderColor=colors.HexColor('#20B2AA'),
                                             borderWidth=1, borderPadding=5)
            cardio_text = f"""<b>🏃 CARDIO: {day.cardio.description}</b><br/>
            Duration: {day.cardio.duration} | Intensity: {day.cardio.intensity}<br/>
            <i>{day.cardio.notes}</i>"""
            story.append(Paragraph(cardio_text, cardio_box_style))
        
        story.append(Spacer(1, 10))
    
    # Build PDF
    doc.build(story)
    print(f"\n📄 Program PDF saved to: {output_path}")

def run_program_audit_for_user(user: UserProfile, duration_weeks: int = 5):
    """Run program generation audit for a specific user with variable duration.
    
    Supports: 5 weeks (standard), 8 weeks (intermediate), 12 weeks (~90 days)
    """
    
    print("=" * 80)
    print(f"{duration_weeks}-WEEK PROGRAM GENERATION AUDIT")
    print("=" * 80)
    
    print(f"\n👤 User: {user.name}")
    print(f"   Age: {user.age}, Gender: {user.gender.value}")
    print(f"   Weight: {user.weight_lbs} lbs")
    print(f"   Experience: {user.experience_level.value}")
    print(f"   Goal: {user.fitness_goal.value}")
    print(f"   Days/Week: {user.available_days_per_week}")
    print(f"   Duration: {duration_weeks} weeks (~{duration_weeks * 7} days)")
    print(f"   Equipment: {', '.join(user.available_equipment)}")
    if user.injuries:
        print(f"   Injuries: {', '.join([f'{i.area} ({i.severity})' for i in user.injuries])}")
    
    print(f"\n📥 Loading exercises from Supabase...")
    all_exercises = []
    offset = 0
    batch_size = 1000
    
    while True:
        batch = fetch_exercises_from_supabase(batch_size, offset)
        if not batch:
            break
        all_exercises.extend(batch)
        offset += batch_size
        if len(batch) < batch_size:
            break
    
    print(f"   Loaded {len(all_exercises)} exercises")
    
    # Generate the program with specified duration
    program = generate_program(user, all_exercises, duration_weeks=duration_weeks)
    
    # Generate PDF
    output_path = "/Users/josephreed/Desktop/Workout App/5_Week_Program_Audit.pdf"
    generate_program_pdf(program, output_path)
    
    # Summary
    print("\n" + "=" * 80)
    print("PROGRAM GENERATION COMPLETE")
    print("=" * 80)
    print(f"User: {user.name}")
    print(f"Program: {program.program_name}")
    print(f"Duration: {program.duration_weeks} weeks (~{program.duration_weeks * 7} days)")
    print(f"Total Training Days: {program.total_days}")
    print(f"Exercises per day: ~{sum(len(d.exercises) for d in program.days) // len(program.days)}")
    
    return program

def run_program_audit():
    """Run the 5-week program generation audit with default user"""
    
    print("=" * 80)
    print("5-WEEK PROGRAM GENERATION AUDIT")
    print("=" * 80)
    
    # Create a single test user
    test_user = UserProfile(
        id=1,
        name="Marcus Thompson",
        age=28,
        gender=Gender.MALE,
        weight_lbs=185,
        height_inches=72,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[],
        workouts_completed=150,
        preferred_workout_duration=60,
        available_days_per_week=4,
        notes="Experienced lifter looking to maximize hypertrophy"
    )
    
    print(f"\n📥 Loading exercises from Supabase...")
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
    
    exercises = all_exercises
    print(f"   Loaded {len(exercises)} exercises")
    
    # Generate the program
    program = generate_program(test_user, exercises, duration_weeks=5)
    
    # Generate PDF
    output_path = "/Users/josephreed/Desktop/Workout App/5_Week_Program_Audit.pdf"
    generate_program_pdf(program, output_path)
    
    # Summary
    print("\n" + "=" * 80)
    print("PROGRAM GENERATION COMPLETE")
    print("=" * 80)
    print(f"User: {test_user.name}")
    print(f"Program: {program.program_name}")
    print(f"Duration: {program.duration_weeks} weeks")
    print(f"Total Training Days: {program.total_days}")
    print(f"Exercises per day: ~{sum(len(d.exercises) for d in program.days) // len(program.days)}")
    
    return program

def generate_random_gym_user() -> UserProfile:
    """Generate a random gym user with diverse profile attributes"""
    import random
    
    # Random attributes
    first_names_male = ["Marcus", "James", "David", "Michael", "Chris", "Alex", "Ryan", "Jake", "Tyler", "Brandon"]
    first_names_female = ["Sarah", "Jessica", "Emily", "Amanda", "Rachel", "Nicole", "Ashley", "Megan", "Lauren", "Brittany"]
    last_names = ["Thompson", "Williams", "Johnson", "Brown", "Davis", "Miller", "Wilson", "Anderson", "Taylor", "Moore"]
    
    gender = random.choice([Gender.MALE, Gender.FEMALE])
    first_name = random.choice(first_names_male if gender == Gender.MALE else first_names_female)
    last_name = random.choice(last_names)
    
    age = random.randint(22, 55)
    weight = random.randint(140, 220) if gender == Gender.MALE else random.randint(120, 180)
    height = random.randint(66, 76) if gender == Gender.MALE else random.randint(60, 70)
    
    experience = random.choice([ExperienceLevel.BEGINNER, ExperienceLevel.INTERMEDIATE, ExperienceLevel.ADVANCED])
    goal = random.choice(list(FitnessGoal))
    days_per_week = random.choice([3, 4, 5])
    duration = random.choice([45, 60, 75])
    
    # Gym equipment variations
    equipment_options = [
        ["Barbell", "Dumbbells", "Cables", "Machines"],
        ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebells"],
        ["Dumbbells", "Cables", "Machines"],
        ["Barbell", "Dumbbells", "Cables", "Machines", "Resistance Bands"],
    ]
    equipment = random.choice(equipment_options)
    
    # Random injury (20% chance)
    injuries = []
    if random.random() < 0.2:
        injury_options = [
            ("Lower Back", "mild", "Occasional lower back tightness"),
            ("Shoulder", "mild", "Minor shoulder discomfort with overhead movements"),
            ("Knee", "mild", "Slight knee pain with deep squats"),
            ("Wrist", "mild", "Wrist sensitivity with heavy pressing"),
        ]
        injury = random.choice(injury_options)
        injuries = [Injury(area=injury[0], severity=injury[1], description=injury[2])]
    
    return UserProfile(
        id=random.randint(1000, 9999),
        name=f"{first_name} {last_name}",
        age=age,
        gender=gender,
        weight_lbs=weight,
        height_inches=height,
        body_type=random.choice(list(BodyType)),
        experience_level=experience,
        fitness_goal=goal,
        workout_location=WorkoutLocation.GYM,
        available_equipment=equipment,
        injuries=injuries,
        workouts_completed=random.randint(0, 200),
        preferred_workout_duration=duration,
        available_days_per_week=days_per_week,
        notes=f"Generated test user - {experience.value} looking to {goal.value}"
    )

def run_multi_user_autogen_test(num_users: int = 10, workouts_per_user: int = 4):
    """
    Run auto-gen workout test for multiple users with varying profiles.
    Generates a PDF with all users and their workouts.
    """
    from reportlab.lib.pagesizes import letter
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    import random
    
    print("=" * 80)
    print(f"MULTI-USER AUTO-GEN WORKOUT AUDIT ({num_users} users, {workouts_per_user} workouts each)")
    print("=" * 80)
    
    # Load exercises once
    print(f"\n📥 Loading exercises from Supabase...")
    all_exercises = fetch_exercises_from_supabase()
    print(f"   Loaded {len(all_exercises)} exercises")
    
    # Define workout target combinations (variety)
    all_workout_targets = [
        ["Chest", "Triceps"],
        ["Back", "Biceps"],
        ["Legs", "Glutes"],
        ["Shoulders", "Abs"],
        ["Chest", "Shoulders"],
        ["Back", "Rear Delts"],
        ["Quads", "Hamstrings"],
        ["Arms"],  # Biceps + Triceps
        ["Push"],  # Chest/Shoulders/Triceps
        ["Pull"],  # Back/Biceps
        ["Core", "Abs"],
        ["Full Body"],
    ]
    
    # Generate diverse users
    users_data = []
    
    for user_num in range(1, num_users + 1):
        user = generate_random_gym_user()
        
        print(f"\n{'='*60}")
        print(f"USER {user_num}: {user.name}")
        print(f"{'='*60}")
        print(f"   Age: {user.age}, Gender: {user.gender.value}")
        print(f"   Experience: {user.experience_level.value}")
        print(f"   Goal: {user.fitness_goal.value}")
        print(f"   Equipment: {', '.join(user.available_equipment)}")
        if user.injuries:
            print(f"   Injuries: {', '.join([f'{i.area} ({i.severity})' for i in user.injuries])}")
        
        # Select 4 different workout targets for this user
        user_targets = random.sample(all_workout_targets, min(workouts_per_user, len(all_workout_targets)))
        
        workout_results = []
        user_recently_used = set()  # Track exercises used by this user for de-duplication
        
        for workout_num, targets in enumerate(user_targets, 1):
            print(f"\n   Generating Workout {workout_num}: {', '.join(targets)}...")
            
            # Expand target muscles for Push/Pull/Full Body
            expanded_targets = targets.copy()
            is_full_body = "Full Body" in targets
            
            if "Push" in targets:
                expanded_targets = ["Chest", "Shoulders", "Triceps"]
            elif "Pull" in targets:
                expanded_targets = ["Back", "Biceps", "Rear Delts"]
            elif "Full Body" in targets:
                # LABEL INTEGRITY: Full Body MUST include lower + push + pull
                # Expanded to ensure all major patterns are represented
                expanded_targets = ["Chest", "Back", "Shoulders", "Legs", "Core"]
            elif "Arms" in targets:
                expanded_targets = ["Biceps", "Triceps"]
            
            # Filter out exercises already used by this user (de-duplication)
            available_exercises = [ex for ex in all_exercises 
                                   if ex.get('name', '') not in user_recently_used]
            
            selected = select_exercises_for_workout(
                exercises=available_exercises,
                target_muscles=expanded_targets,
                user=user,
                count=None  # Use duration-based count
            )
            
            # LABEL INTEGRITY CHECK: Full Body must have push + pull + lower
            if is_full_body and len(selected) > 0:
                patterns_present = set()
                for ex in selected:
                    pattern = classify_movement_pattern(ex.get('name', ''), ex.get('equipment', ''))
                    patterns_present.add(pattern)
                
                has_push = any(p in patterns_present for p in ['horizontal_press', 'vertical_press'])
                has_pull = any(p in patterns_present for p in ['horizontal_pull', 'vertical_pull'])
                has_lower = any(p in patterns_present for p in ['squat', 'hinge', 'lunge', 'leg_press', 'hip_thrust'])
                
                # If missing any major pattern, try to add one
                if not has_push:
                    # Find a push exercise - prefer machine chest press or dumbbell press
                    push_candidates = []
                    for ex in available_exercises:
                        name = ex.get('name', '')
                        if name in user_recently_used:
                            continue
                        pattern = classify_movement_pattern(name, ex.get('equipment', ''))
                        if pattern in ['horizontal_press', 'vertical_press']:
                            equip_ok, _ = check_equipment_match(ex.get('equipment', ''), user.available_equipment, True)
                            if equip_ok:
                                # Skip hanging/pike exercises (not push!)
                                name_lower = name.lower()
                                if "hanging" in name_lower or "pike" in name_lower:
                                    continue
                                # Prefer machine/lever presses
                                priority = 0
                                if "lever" in name_lower or "machine" in name_lower:
                                    priority = 2
                                elif "dumbbell" in name_lower or "cable" in name_lower:
                                    priority = 1
                                push_candidates.append((priority, ex))
                    
                    if push_candidates:
                        push_candidates.sort(key=lambda x: -x[0])
                        selected.append(push_candidates[0][1])
                        print(f"      + Added push: {push_candidates[0][1].get('name')}")
                
                if not has_pull:
                    # Find a pull exercise - prefer machine row or lat pulldown
                    pull_candidates = []
                    for ex in available_exercises:
                        name = ex.get('name', '')
                        if name in user_recently_used:
                            continue
                        pattern = classify_movement_pattern(name, ex.get('equipment', ''))
                        if pattern in ['horizontal_pull', 'vertical_pull']:
                            equip_ok, _ = check_equipment_match(ex.get('equipment', ''), user.available_equipment, True)
                            if equip_ok:
                                name_lower = name.lower()
                                # Skip risky exercises
                                if "upright" in name_lower or "high pull" in name_lower:
                                    continue
                                # Prefer machine/lever rows
                                priority = 0
                                if "lever" in name_lower or "machine" in name_lower:
                                    priority = 2
                                elif "cable" in name_lower or "seated" in name_lower:
                                    priority = 1
                                pull_candidates.append((priority, ex))
                    
                    if pull_candidates:
                        pull_candidates.sort(key=lambda x: -x[0])
                        selected.append(pull_candidates[0][1])
                        print(f"      + Added pull: {pull_candidates[0][1].get('name')}")
            
            # Track used exercises
            for ex in selected:
                user_recently_used.add(ex.get('name', ''))
            
            workout_results.append({
                "workout_num": workout_num,
                "targets": targets,
                "expanded_targets": expanded_targets,
                "exercises": selected
            })
            
            print(f"      ✅ {len(selected)} exercises selected")
        
        users_data.append({
            "user": user,
            "workouts": workout_results
        })
    
    # Generate PDF
    output_path = "/Users/josephreed/Desktop/Workout App/MultiUser_AutoGen_Audit.pdf"
    doc = SimpleDocTemplate(output_path, pagesize=letter,
                           rightMargin=40, leftMargin=40,
                           topMargin=40, bottomMargin=40)
    styles = getSampleStyleSheet()
    
    title_style = ParagraphStyle('Title', parent=styles['Heading1'], fontSize=22, alignment=TA_CENTER, spaceAfter=15)
    user_style = ParagraphStyle('UserHeader', parent=styles['Heading2'], fontSize=16, textColor=colors.darkblue, spaceBefore=10)
    workout_style = ParagraphStyle('WorkoutHeader', parent=styles['Heading3'], fontSize=12, textColor=colors.darkgreen)
    
    story = []
    story.append(Paragraph(f"AUTO-GEN WORKOUT AUDIT", title_style))
    story.append(Paragraph(f"{num_users} Users × {workouts_per_user} Workouts Each", 
                          ParagraphStyle('Subtitle', parent=styles['Normal'], fontSize=12, alignment=TA_CENTER)))
    story.append(Spacer(1, 20))
    
    for user_data in users_data:
        user = user_data["user"]
        workouts = user_data["workouts"]
        
        # User header
        story.append(Paragraph(f"👤 {user.name}", user_style))
        
        # Compact profile
        profile_text = f"<b>Age:</b> {user.age} | <b>Gender:</b> {user.gender.value} | <b>Experience:</b> {user.experience_level.value} | <b>Goal:</b> {user.fitness_goal.value}"
        story.append(Paragraph(profile_text, styles['Normal']))
        
        equip_text = f"<b>Equipment:</b> {', '.join(user.available_equipment)}"
        story.append(Paragraph(equip_text, styles['Normal']))
        
        if user.injuries:
            injury_text = f"<b>Injuries:</b> {', '.join([f'{i.area} ({i.severity})' for i in user.injuries])}"
            story.append(Paragraph(injury_text, styles['Normal']))
        
        story.append(Spacer(1, 10))
        
        # Workouts
        for workout in workouts:
            story.append(Paragraph(f"Workout {workout['workout_num']}: {', '.join(workout['targets'])}", workout_style))
            
            ex_data = [["#", "Exercise", "Equipment", "Pattern"]]
            for i, ex in enumerate(workout['exercises'], 1):
                pattern = classify_movement_pattern(ex.get('name', ''), ex.get('equipment', ''))
                ex_data.append([str(i), ex.get('name', ''), ex.get('equipment', ''), pattern])
            
            ex_table = Table(ex_data, colWidths=[20, 200, 130, 80])
            ex_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#4A90D9')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
                ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                ('ALIGN', (0, 0), (0, -1), 'CENTER'),
            ]))
            story.append(ex_table)
            story.append(Spacer(1, 8))
        
        story.append(PageBreak())
    
    doc.build(story)
    print(f"\n📄 Multi-user auto-gen PDF saved to: {output_path}")
    
    return users_data

def run_autogen_test(user: UserProfile = None):
    """Run auto-gen workout test for a single user"""
    if user is None:
        user = generate_random_gym_user()
    
    print("=" * 80)
    print("AUTO-GEN WORKOUT TEST")
    print("=" * 80)
    print(f"\n👤 Testing user: {user.name}")
    print(f"   Age: {user.age}, Gender: {user.gender.value}")
    print(f"   Experience: {user.experience_level.value}")
    print(f"   Goal: {user.fitness_goal.value}")
    print(f"   Equipment: {', '.join(user.available_equipment)}")
    print(f"   Duration: {user.preferred_workout_duration} min")
    if user.injuries:
        print(f"   Injuries: {', '.join([f'{i.area} ({i.severity})' for i in user.injuries])}")
    
    # Load exercises
    print(f"\n📥 Loading exercises from Supabase...")
    all_exercises = []
    offset = 0
    batch_size = 1000
    while True:
        batch = fetch_exercises_from_supabase(batch_size, offset)
        if not batch:
            break
        all_exercises.extend(batch)
        offset += batch_size
        if len(batch) < batch_size:
            break
    
    print(f"   Loaded {len(all_exercises)} exercises")
    
    # Generate 2 workouts for this user
    from datetime import datetime
    workout_results = []
    
    workout_targets = [
        ["Chest", "Triceps"],
        ["Back", "Biceps"],
    ]
    
    for i, targets in enumerate(workout_targets, 1):
        print(f"\n{'='*60}")
        print(f"GENERATING WORKOUT {i}: {', '.join(targets)}")
        print(f"{'='*60}")
        
        # Use existing workout selection logic
        selected = select_exercises_for_workout(
            exercises=all_exercises,
            target_muscles=targets,
            user=user,
            count=6
        )
        
        workout_results.append({
            "workout_num": i,
            "targets": targets,
            "exercises": selected
        })
        
        print(f"\n✅ Workout {i} - {len(selected)} exercises selected")
    
    # Generate simple PDF report
    from reportlab.lib.pagesizes import letter
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    
    output_path = "/Users/josephreed/Desktop/Workout App/AutoGen_Workout_Audit.pdf"
    doc = SimpleDocTemplate(output_path, pagesize=letter)
    styles = getSampleStyleSheet()
    
    title_style = ParagraphStyle('Title', parent=styles['Heading1'], fontSize=24, alignment=TA_CENTER, spaceAfter=20)
    
    story = []
    story.append(Paragraph("AUTO-GEN WORKOUT AUDIT", title_style))
    story.append(Spacer(1, 20))
    
    # User profile
    story.append(Paragraph("USER PROFILE", styles['Heading2']))
    profile_data = [
        ["Name", user.name],
        ["Age", str(user.age)],
        ["Gender", user.gender.value],
        ["Experience", user.experience_level.value],
        ["Goal", user.fitness_goal.value],
        ["Equipment", ", ".join(user.available_equipment)],
        ["Duration", f"{user.preferred_workout_duration} min"],
    ]
    if user.injuries:
        profile_data.append(["Injuries", ", ".join([f"{i.area} ({i.severity})" for i in user.injuries])])
    
    profile_table = Table(profile_data, colWidths=[120, 300])
    profile_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.lightgrey),
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
    ]))
    story.append(profile_table)
    story.append(Spacer(1, 20))
    
    # Workouts
    for result in workout_results:
        story.append(Paragraph(f"WORKOUT {result['workout_num']}: {', '.join(result['targets'])}", styles['Heading2']))
        
        ex_data = [["#", "Exercise", "Equipment", "Pattern"]]
        for i, ex in enumerate(result['exercises'], 1):
            pattern = classify_movement_pattern(ex.get('name', ''), ex.get('equipment', ''))
            ex_data.append([str(i), ex.get('name', ''), ex.get('equipment', ''), pattern])
        
        ex_table = Table(ex_data, colWidths=[25, 220, 120, 80])
        ex_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.darkblue),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, -1), 9),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ]))
        story.append(ex_table)
        story.append(Spacer(1, 15))
    
    doc.build(story)
    print(f"\n📄 Auto-gen audit PDF saved to: {output_path}")
    
    return workout_results

if __name__ == "__main__":
    import sys
    import random
    
    if len(sys.argv) > 1:
        mode = sys.argv[1]
        
        if mode == "--program":
            # Run program generation mode (default user)
            run_program_audit()
        elif mode == "--program-random":
            # Run program generation with random user (random duration: 5, 8, or 12 weeks)
            duration = random.choice([5, 8, 12])
            run_program_audit_for_user(generate_random_gym_user(), duration_weeks=duration)
        elif mode == "--program-12week":
            # Run 12-week (90 day) program with random user
            run_program_audit_for_user(generate_random_gym_user(), duration_weeks=12)
        elif mode == "--program-8week":
            # Run 8-week program with random user
            run_program_audit_for_user(generate_random_gym_user(), duration_weeks=8)
        elif mode == "--autogen":
            # Run auto-gen test with random user
            run_autogen_test()
        else:
            print(f"Unknown mode: {mode}")
            print("Usage:")
            print("  --program          : Generate 5-week program for default user")
            print("  --program-random   : Generate random duration (5/8/12 week) program for random gym user")
            print("  --program-12week   : Generate 12-week (~90 day) program for random gym user")
            print("  --program-8week    : Generate 8-week program for random gym user")
            print("  --autogen          : Generate 2 auto-gen workouts for random gym user")
    else:
        # Run standard workout audit (20 users)
        main()

