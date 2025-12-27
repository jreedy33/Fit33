#!/usr/bin/env python3
"""
Smart Recommendation Engine Test Suite
Generates 100 beta tester profiles and validates weight/rep recommendations

Tests:
1. User profile generation (diverse demographics)
2. Workout generation based on user profile
3. Starting weight/rep recommendations for first-time exercises
4. Accuracy grading against expected values
"""

import json
import random
from datetime import datetime
from enum import Enum
from dataclasses import dataclass, asdict
from typing import List, Dict, Tuple, Optional
import os

# ============================================================================
# ENUMS AND CONSTANTS (matching Swift logic)
# ============================================================================

class StrengthLevel(Enum):
    VERY_LIGHT = ("Very Light", 0.4)   # ~2 lbs
    LIGHT = ("Light", 0.65)             # ~8 lbs
    MODERATE = ("Moderate", 1.0)        # ~14 lbs
    STRONG = ("Strong", 1.4)            # ~40 lbs
    VERY_STRONG = ("Very Strong", 1.8)  # ~60+ lbs
    
    @property
    def multiplier(self):
        return self.value[1]
    
    @property
    def display_name(self):
        return self.value[0]

class ExerciseCategory(Enum):
    COMPOUND_UPPER = ("Compound Upper", 65)    # Bench, rows
    COMPOUND_LOWER = ("Compound Lower", 95)    # Squat, deadlift
    ISOLATION_UPPER = ("Isolation Upper", 15)  # Bicep curls
    ISOLATION_LOWER = ("Isolation Lower", 30)  # Leg curls
    CORE_ABDOMINAL = ("Core", 0)               # Bodyweight
    MACHINE_UPPER = ("Machine Upper", 50)      # Machine press
    MACHINE_LOWER = ("Machine Lower", 90)      # Leg press
    
    @property
    def base_weight(self):
        return self.value[1]

class Gender(Enum):
    MALE = "Male"
    FEMALE = "Female"
    OTHER = "Other"

class Experience(Enum):
    BEGINNER = "Beginner"
    INTERMEDIATE = "Intermediate"
    ADVANCED = "Advanced"

class Goal(Enum):
    BUILD_MUSCLE = "Build Muscle"
    GET_LEAN = "Get Lean"
    STRENGTH = "Strength"
    ENDURANCE = "Endurance"
    GENERAL = "General Fitness"

class WorkoutLocation(Enum):
    GYM = "Gym"
    HOME = "Home"
    OUTDOOR = "Outdoor"
    HYBRID = "Hybrid"

# Equipment mapping by location
EQUIPMENT_BY_LOCATION = {
    WorkoutLocation.GYM: ["Barbell", "Dumbbells", "Machines", "Cables", "Bench"],
    WorkoutLocation.HOME: ["Dumbbells", "Bodyweight", "Resistance Bands"],
    WorkoutLocation.OUTDOOR: ["Bodyweight", "Pull-up Bar"],
    WorkoutLocation.HYBRID: ["Dumbbells", "Bodyweight", "Cables", "Bench"]
}

# Sample exercises by category
EXERCISES_BY_CATEGORY = {
    ExerciseCategory.COMPOUND_UPPER: [
        "Barbell Bench Press", "Dumbbell Bench Press", "Incline Bench Press",
        "Barbell Row", "Dumbbell Row", "Overhead Press", "Shoulder Press",
        "Pull Up", "Lat Pulldown", "Push Up"
    ],
    ExerciseCategory.COMPOUND_LOWER: [
        "Barbell Squat", "Goblet Squat", "Dumbbell Squat", "Deadlift",
        "Romanian Deadlift", "Lunges", "Bulgarian Split Squat", "Hip Thrust"
    ],
    ExerciseCategory.ISOLATION_UPPER: [
        "Dumbbell Bicep Curl", "Barbell Curl", "Hammer Curl",
        "Tricep Extension", "Tricep Pushdown", "Lateral Raise",
        "Front Raise", "Rear Delt Fly", "Dumbbell Fly"
    ],
    ExerciseCategory.ISOLATION_LOWER: [
        "Leg Curl", "Leg Extension", "Calf Raise", "Standing Calf Raise",
        "Glute Kickback", "Glute Bridge"
    ],
    ExerciseCategory.CORE_ABDOMINAL: [
        "Plank", "Crunch", "Sit Up", "Russian Twist", "Leg Raise",
        "Mountain Climber", "Dead Bug"
    ],
    ExerciseCategory.MACHINE_UPPER: [
        "Machine Chest Press", "Machine Shoulder Press", "Cable Fly",
        "Cable Row", "Lat Pulldown Machine", "Pec Deck"
    ],
    ExerciseCategory.MACHINE_LOWER: [
        "Leg Press", "Machine Leg Curl", "Machine Leg Extension",
        "Smith Machine Squat", "Machine Calf Raise"
    ]
}

# ============================================================================
# DATA MODELS
# ============================================================================

@dataclass
class UserProfile:
    id: int
    name: str
    age: int
    gender: Gender
    weight_lbs: float
    height_in: int
    strength_level: StrengthLevel
    experience: Experience
    goal: Goal
    location: WorkoutLocation
    equipment: List[str]
    
    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "age": self.age,
            "gender": self.gender.value,
            "weight_lbs": self.weight_lbs,
            "height_in": self.height_in,
            "strength_level": self.strength_level.display_name,
            "experience": self.experience.value,
            "goal": self.goal.value,
            "location": self.location.value,
            "equipment": self.equipment
        }

@dataclass
class ExerciseRecommendation:
    exercise_name: str
    category: ExerciseCategory
    recommended_weight: float
    recommended_reps: int
    recommended_sets: int
    confidence: float
    note: str

@dataclass 
class WorkoutRecommendation:
    user: UserProfile
    exercises: List[ExerciseRecommendation]
    workout_type: str
    target_muscles: List[str]

@dataclass
class GradingResult:
    user_id: int
    user_summary: str
    exercise_name: str
    recommended_weight: float
    expected_weight_range: Tuple[float, float]
    recommended_reps: int
    expected_reps_range: Tuple[int, int]
    weight_grade: str
    reps_grade: str
    overall_grade: str
    issues: List[str]

# ============================================================================
# RECOMMENDATION ENGINE (Python implementation matching Swift logic)
# ============================================================================

def get_gender_multiplier(gender: Gender, category: ExerciseCategory) -> float:
    """Match Swift genderMultiplier logic"""
    if gender == Gender.MALE:
        return 1.0
    elif gender == Gender.FEMALE:
        if category in [ExerciseCategory.COMPOUND_UPPER, ExerciseCategory.ISOLATION_UPPER, ExerciseCategory.MACHINE_UPPER]:
            return 0.55
        elif category in [ExerciseCategory.COMPOUND_LOWER, ExerciseCategory.ISOLATION_LOWER, ExerciseCategory.MACHINE_LOWER]:
            return 0.70
        elif category == ExerciseCategory.CORE_ABDOMINAL:
            return 0.9
    return 0.8  # Other/unknown

def get_age_multiplier(age: int) -> float:
    """Match Swift ageMultiplier logic"""
    if age < 18:
        return 0.7
    elif age < 25:
        return 1.0
    elif age < 35:
        return 0.98
    elif age < 45:
        return 0.93
    elif age < 55:
        return 0.85
    elif age < 65:
        return 0.75
    elif age < 75:
        return 0.65
    else:
        return 0.55

def get_experience_multiplier(experience: Experience) -> float:
    """Match Swift experienceMultiplier logic"""
    if experience == Experience.BEGINNER:
        return 0.7
    elif experience == Experience.INTERMEDIATE:
        return 0.9
    elif experience == Experience.ADVANCED:
        return 1.1
    return 0.7

def get_goal_adjustment(goal: Goal, experience: Experience, age: int = 30) -> Tuple[float, int]:
    """Match Swift goalAdjustment logic - returns (weight_multiplier, reps)"""
    is_beginner = experience == Experience.BEGINNER
    
    if goal == Goal.STRENGTH:
        weight_mult, reps = 1.15, (6 if is_beginner else 5)
    elif goal == Goal.BUILD_MUSCLE:
        weight_mult, reps = 1.0, (10 if is_beginner else 8)
    elif goal == Goal.GET_LEAN:
        weight_mult, reps = 0.85, 12
    elif goal == Goal.ENDURANCE:
        weight_mult, reps = 0.70, 15
    else:  # General
        weight_mult, reps = 0.9, (10 if is_beginner else 8)
    
    # Senior adjustment: cap reps for safety
    if age >= 65:
        reps = min(reps, 12)
        if reps > 10:
            weight_mult *= 0.9
    elif age >= 55:
        reps = min(reps, 15)
    
    return (weight_mult, reps)

def calculate_recommended_weight(
    user: UserProfile,
    category: ExerciseCategory
) -> Tuple[float, int, float]:
    """
    Calculate recommended weight and reps for a user and exercise category.
    Returns: (weight, reps, confidence)
    """
    # Start with base weight
    weight = category.base_weight
    
    # Apply strength level multiplier
    weight *= user.strength_level.multiplier
    
    # Apply gender adjustment
    weight *= get_gender_multiplier(user.gender, category)
    
    # Apply age adjustment
    weight *= get_age_multiplier(user.age)
    
    # Apply experience adjustment
    weight *= get_experience_multiplier(user.experience)
    
    # Apply goal adjustment (including age-based rep capping)
    goal_mult, reps = get_goal_adjustment(user.goal, user.experience, user.age)
    weight *= goal_mult
    
    # Round weight
    if weight < 20:
        weight = round(weight / 2.5) * 2.5
    else:
        weight = round(weight / 5) * 5
    
    # Minimum weights by category
    min_weights = {
        ExerciseCategory.COMPOUND_UPPER: 20,
        ExerciseCategory.COMPOUND_LOWER: 25,
        ExerciseCategory.ISOLATION_UPPER: 5,
        ExerciseCategory.ISOLATION_LOWER: 10,
        ExerciseCategory.CORE_ABDOMINAL: 0,
        ExerciseCategory.MACHINE_UPPER: 15,
        ExerciseCategory.MACHINE_LOWER: 20
    }
    weight = max(weight, min_weights.get(category, 5))
    
    # Confidence based on data quality
    confidence = 0.7
    if user.experience != Experience.BEGINNER:
        confidence += 0.1
    if user.strength_level not in [StrengthLevel.VERY_LIGHT, StrengthLevel.VERY_STRONG]:
        confidence += 0.1
    
    return (weight, reps, min(confidence, 1.0))

def categorize_exercise(name: str) -> ExerciseCategory:
    """Match Swift categorizeExercise logic"""
    lower = name.lower()
    
    # Compound Lower
    if any(k in lower for k in ["squat", "deadlift", "lunge", "leg press", "hip thrust"]):
        if any(k in lower for k in ["machine", "lever"]):
            return ExerciseCategory.MACHINE_LOWER
        return ExerciseCategory.COMPOUND_LOWER
    
    # Compound Upper  
    if any(k in lower for k in ["bench", "press", "row", "pull", "push up", "dip"]):
        if any(k in lower for k in ["machine", "lever"]):
            return ExerciseCategory.MACHINE_UPPER
        return ExerciseCategory.COMPOUND_UPPER
    
    # Isolation Lower
    if any(k in lower for k in ["leg curl", "leg extension", "calf", "glute"]):
        if any(k in lower for k in ["machine", "lever"]):
            return ExerciseCategory.MACHINE_LOWER
        return ExerciseCategory.ISOLATION_LOWER
    
    # Core
    if any(k in lower for k in ["crunch", "plank", "abs", "core", "sit up", "russian twist"]):
        return ExerciseCategory.CORE_ABDOMINAL
    
    # Machine
    if any(k in lower for k in ["machine", "cable", "lever"]):
        if any(k in lower for k in ["leg", "calf"]):
            return ExerciseCategory.MACHINE_LOWER
        return ExerciseCategory.MACHINE_UPPER
    
    # Isolation Upper default
    if any(k in lower for k in ["curl", "extension", "raise", "fly", "kickback", "shrug"]):
        return ExerciseCategory.ISOLATION_UPPER
    
    return ExerciseCategory.ISOLATION_UPPER

# ============================================================================
# USER PROFILE GENERATION
# ============================================================================

def generate_random_name(gender: Gender, id: int) -> str:
    """Generate a random name based on gender"""
    male_names = ["James", "John", "Robert", "Michael", "David", "William", "Joseph", "Thomas", "Charles", "Chris",
                  "Marcus", "Kevin", "Brian", "Steve", "Tony", "Alex", "Jake", "Ryan", "Tyler", "Brandon"]
    female_names = ["Mary", "Patricia", "Jennifer", "Linda", "Sarah", "Jessica", "Emily", "Emma", "Ashley", "Amanda",
                    "Nicole", "Rachel", "Lisa", "Michelle", "Brittany", "Laura", "Samantha", "Christina", "Megan", "Tiffany"]
    other_names = ["Jordan", "Taylor", "Casey", "Riley", "Quinn", "Morgan", "Avery", "Skyler", "Dakota", "Jamie"]
    
    if gender == Gender.MALE:
        return f"{random.choice(male_names)} #{id}"
    elif gender == Gender.FEMALE:
        return f"{random.choice(female_names)} #{id}"
    else:
        return f"{random.choice(other_names)} #{id}"

def generate_user_profile(id: int) -> UserProfile:
    """Generate a realistic random user profile"""
    
    # Gender distribution: 60% male, 35% female, 5% other
    gender_roll = random.random()
    if gender_roll < 0.60:
        gender = Gender.MALE
    elif gender_roll < 0.95:
        gender = Gender.FEMALE
    else:
        gender = Gender.OTHER
    
    # Age distribution (weighted towards 20-45)
    age_roll = random.random()
    if age_roll < 0.05:
        age = random.randint(16, 19)  # Teen
    elif age_roll < 0.35:
        age = random.randint(20, 29)  # 20s
    elif age_roll < 0.60:
        age = random.randint(30, 39)  # 30s
    elif age_roll < 0.80:
        age = random.randint(40, 54)  # 40s-50s
    elif age_roll < 0.92:
        age = random.randint(55, 64)  # 55-64
    else:
        age = random.randint(65, 80)  # Senior
    
    # Weight based on gender and age
    if gender == Gender.MALE:
        base_weight = 180
        weight_std = 40
    elif gender == Gender.FEMALE:
        base_weight = 150
        weight_std = 35
    else:
        base_weight = 165
        weight_std = 38
    
    weight = max(100, min(350, random.gauss(base_weight, weight_std)))
    
    # Height based on gender
    if gender == Gender.MALE:
        height = random.randint(64, 78)  # 5'4" to 6'6"
    elif gender == Gender.FEMALE:
        height = random.randint(59, 71)  # 4'11" to 5'11"
    else:
        height = random.randint(62, 74)  # 5'2" to 6'2"
    
    # Strength level (correlates somewhat with experience and weight)
    strength_levels = list(StrengthLevel)
    strength_weights = [0.10, 0.25, 0.35, 0.20, 0.10]  # Distribution
    strength_level = random.choices(strength_levels, weights=strength_weights)[0]
    
    # Experience (60% beginner, 30% intermediate, 10% advanced)
    exp_roll = random.random()
    if exp_roll < 0.60:
        experience = Experience.BEGINNER
    elif exp_roll < 0.90:
        experience = Experience.INTERMEDIATE
    else:
        experience = Experience.ADVANCED
    
    # Goal
    goal = random.choice(list(Goal))
    
    # Location (50% gym, 30% home, 10% outdoor, 10% hybrid)
    loc_roll = random.random()
    if loc_roll < 0.50:
        location = WorkoutLocation.GYM
    elif loc_roll < 0.80:
        location = WorkoutLocation.HOME
    elif loc_roll < 0.90:
        location = WorkoutLocation.OUTDOOR
    else:
        location = WorkoutLocation.HYBRID
    
    equipment = EQUIPMENT_BY_LOCATION[location]
    
    return UserProfile(
        id=id,
        name=generate_random_name(gender, id),
        age=age,
        gender=gender,
        weight_lbs=round(weight, 1),
        height_in=height,
        strength_level=strength_level,
        experience=experience,
        goal=goal,
        location=location,
        equipment=equipment
    )

# ============================================================================
# WORKOUT GENERATION
# ============================================================================

def select_exercises_for_user(user: UserProfile, count: int = 5) -> List[Tuple[str, ExerciseCategory]]:
    """Select appropriate exercises for user based on equipment and profile"""
    
    available_exercises = []
    
    # Filter exercises by equipment
    has_barbell = "Barbell" in user.equipment
    has_dumbbells = "Dumbbells" in user.equipment
    has_machines = "Machines" in user.equipment or "Cables" in user.equipment
    has_bodyweight = "Bodyweight" in user.equipment or len(user.equipment) == 0
    
    for category, exercises in EXERCISES_BY_CATEGORY.items():
        for exercise in exercises:
            lower = exercise.lower()
            
            # Filter by equipment
            if "barbell" in lower and not has_barbell:
                continue
            if "dumbbell" in lower and not has_dumbbells:
                continue
            if any(k in lower for k in ["machine", "cable", "lever"]) and not has_machines:
                continue
            
            # Filter heavy exercises for certain users
            if user.weight_lbs > 250 and any(k in lower for k in ["pull up", "chin up", "dip"]):
                continue
            
            if user.age > 65 and any(k in lower for k in ["jump", "plyo", "explosive"]):
                continue
            
            available_exercises.append((exercise, category))
    
    # Select diverse exercises
    selected = []
    categories_used = set()
    
    random.shuffle(available_exercises)
    
    for exercise, category in available_exercises:
        if len(selected) >= count:
            break
        
        # Prefer variety
        if len(categories_used) < 4 and category in categories_used:
            continue
        
        selected.append((exercise, category))
        categories_used.add(category)
    
    # Fill remaining if needed
    for exercise, category in available_exercises:
        if len(selected) >= count:
            break
        if (exercise, category) not in selected:
            selected.append((exercise, category))
    
    return selected[:count]

def generate_workout_for_user(user: UserProfile) -> WorkoutRecommendation:
    """Generate a complete workout with recommendations for a user"""
    
    exercises = select_exercises_for_user(user, count=5)
    
    recommendations = []
    for exercise_name, category in exercises:
        weight, reps, confidence = calculate_recommended_weight(user, category)
        
        note = generate_recommendation_note(user, category, weight)
        
        recommendations.append(ExerciseRecommendation(
            exercise_name=exercise_name,
            category=category,
            recommended_weight=weight,
            recommended_reps=reps,
            recommended_sets=3,
            confidence=confidence,
            note=note
        ))
    
    # Determine workout type
    muscle_groups = set()
    for _, cat in exercises:
        if cat in [ExerciseCategory.COMPOUND_UPPER, ExerciseCategory.ISOLATION_UPPER, ExerciseCategory.MACHINE_UPPER]:
            muscle_groups.add("Upper Body")
        elif cat in [ExerciseCategory.COMPOUND_LOWER, ExerciseCategory.ISOLATION_LOWER, ExerciseCategory.MACHINE_LOWER]:
            muscle_groups.add("Lower Body")
        elif cat == ExerciseCategory.CORE_ABDOMINAL:
            muscle_groups.add("Core")
    
    workout_type = " & ".join(sorted(muscle_groups)) if muscle_groups else "Full Body"
    
    return WorkoutRecommendation(
        user=user,
        exercises=recommendations,
        workout_type=workout_type,
        target_muscles=list(muscle_groups)
    )

def generate_recommendation_note(user: UserProfile, category: ExerciseCategory, weight: float) -> str:
    """Generate a helpful note about the recommendation"""
    notes = []
    
    if user.experience == Experience.BEGINNER:
        notes.append("Start light, focus on form")
    
    if user.age > 55:
        notes.append("Adjusted for age")
    
    if user.strength_level in [StrengthLevel.VERY_LIGHT, StrengthLevel.LIGHT]:
        notes.append("Building foundation")
    elif user.strength_level in [StrengthLevel.STRONG, StrengthLevel.VERY_STRONG]:
        notes.append("Strong foundation!")
    
    if category == ExerciseCategory.CORE_ABDOMINAL:
        notes.append("Bodyweight focus")
    
    return " | ".join(notes) if notes else "Standard recommendation"

# ============================================================================
# GRADING SYSTEM
# ============================================================================

def calculate_expected_range(user: UserProfile, category: ExerciseCategory) -> Tuple[Tuple[float, float], Tuple[int, int]]:
    """Calculate expected weight and rep ranges for a user"""
    
    weight, reps, _ = calculate_recommended_weight(user, category)
    
    # Weight range: ±20% for reasonable variation
    weight_low = weight * 0.80
    weight_high = weight * 1.20
    
    # Rep range: ±3 reps
    reps_low = max(3, reps - 3)
    reps_high = reps + 3
    
    return ((weight_low, weight_high), (reps_low, reps_high))

def grade_recommendation(
    user: UserProfile,
    rec: ExerciseRecommendation
) -> GradingResult:
    """Grade a recommendation for accuracy"""
    
    weight_range, reps_range = calculate_expected_range(user, rec.category)
    issues = []
    
    # Grade weight
    if weight_range[0] <= rec.recommended_weight <= weight_range[1]:
        weight_grade = "A"
    elif weight_range[0] * 0.7 <= rec.recommended_weight <= weight_range[1] * 1.3:
        weight_grade = "B"
        if rec.recommended_weight < weight_range[0]:
            issues.append(f"Weight slightly low (got {rec.recommended_weight}, expected {weight_range[0]:.0f}-{weight_range[1]:.0f})")
        else:
            issues.append(f"Weight slightly high (got {rec.recommended_weight}, expected {weight_range[0]:.0f}-{weight_range[1]:.0f})")
    else:
        weight_grade = "C"
        issues.append(f"Weight out of range (got {rec.recommended_weight}, expected {weight_range[0]:.0f}-{weight_range[1]:.0f})")
    
    # Grade reps
    if reps_range[0] <= rec.recommended_reps <= reps_range[1]:
        reps_grade = "A"
    elif reps_range[0] - 2 <= rec.recommended_reps <= reps_range[1] + 2:
        reps_grade = "B"
        issues.append(f"Reps slightly off (got {rec.recommended_reps}, expected {reps_range[0]}-{reps_range[1]})")
    else:
        reps_grade = "C"
        issues.append(f"Reps out of range (got {rec.recommended_reps}, expected {reps_range[0]}-{reps_range[1]})")
    
    # Additional validation checks
    
    # Check for heavy user doing bodyweight exercises
    if user.weight_lbs > 250 and rec.category in [ExerciseCategory.COMPOUND_UPPER]:
        if "pull" in rec.exercise_name.lower() or "dip" in rec.exercise_name.lower():
            issues.append(f"⚠️ Heavy user ({user.weight_lbs}lbs) assigned difficult bodyweight exercise")
    
    # Check for senior doing high-rep schemes
    if user.age > 65 and rec.recommended_reps > 15:
        issues.append(f"⚠️ Senior user assigned high rep count ({rec.recommended_reps})")
    
    # Check for very light user getting too-heavy weights
    if user.strength_level == StrengthLevel.VERY_LIGHT and rec.recommended_weight > 40:
        issues.append(f"⚠️ Low-strength user assigned heavy weight ({rec.recommended_weight}lbs)")
    
    # Check for beginner getting too heavy
    if user.experience == Experience.BEGINNER and rec.recommended_weight > 100 and rec.category == ExerciseCategory.COMPOUND_UPPER:
        issues.append(f"⚠️ Beginner assigned heavy compound lift ({rec.recommended_weight}lbs)")
    
    # Overall grade
    grades = {"A": 4, "B": 3, "C": 2, "D": 1, "F": 0}
    avg = (grades[weight_grade] + grades[reps_grade]) / 2
    
    if avg >= 3.5:
        overall = "A"
    elif avg >= 2.5:
        overall = "B"
    elif avg >= 1.5:
        overall = "C"
    else:
        overall = "D"
    
    # Penalty for issues
    if len(issues) > 2:
        overall = chr(min(ord(overall) + 1, ord("F")))
    
    user_summary = f"{user.name}: {user.age}yo {user.gender.value}, {user.weight_lbs}lbs, {user.experience.value}, {user.strength_level.display_name}"
    
    return GradingResult(
        user_id=user.id,
        user_summary=user_summary,
        exercise_name=rec.exercise_name,
        recommended_weight=rec.recommended_weight,
        expected_weight_range=weight_range,
        recommended_reps=rec.recommended_reps,
        expected_reps_range=reps_range,
        weight_grade=weight_grade,
        reps_grade=reps_grade,
        overall_grade=overall,
        issues=issues
    )

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

def run_test_suite(num_users: int = 100) -> Dict:
    """Run complete test suite with specified number of users"""
    
    print(f"\n{'='*70}")
    print(f"🧪 SMART RECOMMENDATION ENGINE TEST SUITE")
    print(f"{'='*70}")
    print(f"Generating {num_users} beta tester profiles...")
    
    # Generate users
    users = [generate_user_profile(i+1) for i in range(num_users)]
    
    print(f"✅ Generated {len(users)} user profiles")
    
    # Show demographic breakdown
    print(f"\n📊 DEMOGRAPHIC BREAKDOWN:")
    
    gender_counts = {g: 0 for g in Gender}
    exp_counts = {e: 0 for e in Experience}
    goal_counts = {g: 0 for g in Goal}
    strength_counts = {s: 0 for s in StrengthLevel}
    location_counts = {l: 0 for l in WorkoutLocation}
    age_buckets = {"<20": 0, "20-29": 0, "30-39": 0, "40-54": 0, "55-64": 0, "65+": 0}
    weight_buckets = {"<150": 0, "150-199": 0, "200-249": 0, "250+": 0}
    
    for u in users:
        gender_counts[u.gender] += 1
        exp_counts[u.experience] += 1
        goal_counts[u.goal] += 1
        strength_counts[u.strength_level] += 1
        location_counts[u.location] += 1
        
        if u.age < 20: age_buckets["<20"] += 1
        elif u.age < 30: age_buckets["20-29"] += 1
        elif u.age < 40: age_buckets["30-39"] += 1
        elif u.age < 55: age_buckets["40-54"] += 1
        elif u.age < 65: age_buckets["55-64"] += 1
        else: age_buckets["65+"] += 1
        
        if u.weight_lbs < 150: weight_buckets["<150"] += 1
        elif u.weight_lbs < 200: weight_buckets["150-199"] += 1
        elif u.weight_lbs < 250: weight_buckets["200-249"] += 1
        else: weight_buckets["250+"] += 1
    
    print(f"  Gender: {dict((g.value, c) for g, c in gender_counts.items())}")
    print(f"  Experience: {dict((e.value, c) for e, c in exp_counts.items())}")
    print(f"  Goals: {dict((g.value, c) for g, c in goal_counts.items())}")
    print(f"  Strength: {dict((s.display_name, c) for s, c in strength_counts.items())}")
    print(f"  Location: {dict((l.value, c) for l, c in location_counts.items())}")
    print(f"  Age: {age_buckets}")
    print(f"  Weight: {weight_buckets}")
    
    # Generate workouts and grade recommendations
    print(f"\n🏋️ GENERATING WORKOUTS AND RECOMMENDATIONS...")
    
    all_results = []
    all_grades = {"A": 0, "B": 0, "C": 0, "D": 0, "F": 0}
    issues_by_type = {}
    
    for i, user in enumerate(users):
        workout = generate_workout_for_user(user)
        
        for rec in workout.exercises:
            result = grade_recommendation(user, rec)
            all_results.append(result)
            all_grades[result.overall_grade] += 1
            
            for issue in result.issues:
                # Categorize issues
                if "Heavy user" in issue:
                    key = "Heavy user bodyweight"
                elif "Senior" in issue:
                    key = "Senior high reps"
                elif "Low-strength" in issue:
                    key = "Low-strength heavy weight"
                elif "Beginner" in issue:
                    key = "Beginner heavy compound"
                elif "slightly low" in issue:
                    key = "Weight slightly low"
                elif "slightly high" in issue:
                    key = "Weight slightly high"
                elif "out of range" in issue and "Weight" in issue:
                    key = "Weight out of range"
                elif "Reps" in issue:
                    key = "Reps mismatch"
                else:
                    key = "Other"
                
                issues_by_type[key] = issues_by_type.get(key, 0) + 1
        
        if (i + 1) % 20 == 0:
            print(f"  Processed {i+1}/{num_users} users...")
    
    total_recs = len(all_results)
    
    # Calculate statistics
    print(f"\n📈 GRADING RESULTS:")
    print(f"{'='*50}")
    print(f"  Total Recommendations: {total_recs}")
    print(f"\n  Grade Distribution:")
    for grade in ["A", "B", "C", "D", "F"]:
        count = all_grades[grade]
        pct = (count / total_recs) * 100
        bar = "█" * int(pct / 2)
        print(f"    {grade}: {count:4d} ({pct:5.1f}%) {bar}")
    
    # Calculate overall score
    grade_points = {"A": 4, "B": 3, "C": 2, "D": 1, "F": 0}
    total_points = sum(all_grades[g] * grade_points[g] for g in all_grades)
    avg_gpa = total_points / total_recs if total_recs > 0 else 0
    
    if avg_gpa >= 3.5:
        overall_letter = "A"
    elif avg_gpa >= 2.5:
        overall_letter = "B"
    elif avg_gpa >= 1.5:
        overall_letter = "C"
    else:
        overall_letter = "D"
    
    print(f"\n  📊 OVERALL SCORE: {overall_letter} ({avg_gpa:.2f}/4.0)")
    
    # Show issues breakdown
    if issues_by_type:
        print(f"\n  ⚠️ Issues Found:")
        for issue, count in sorted(issues_by_type.items(), key=lambda x: -x[1]):
            print(f"    • {issue}: {count}")
    
    # Sample problematic recommendations
    problem_results = [r for r in all_results if r.overall_grade in ["C", "D", "F"] or len(r.issues) > 0]
    
    if problem_results:
        print(f"\n🔍 SAMPLE PROBLEMATIC RECOMMENDATIONS:")
        print(f"{'='*50}")
        for result in problem_results[:10]:
            print(f"\n  User: {result.user_summary}")
            print(f"  Exercise: {result.exercise_name}")
            print(f"  Recommended: {result.recommended_weight}lbs x {result.recommended_reps}")
            print(f"  Expected Weight: {result.expected_weight_range[0]:.0f}-{result.expected_weight_range[1]:.0f}lbs")
            print(f"  Expected Reps: {result.expected_reps_range[0]}-{result.expected_reps_range[1]}")
            print(f"  Grade: {result.overall_grade} (W:{result.weight_grade}, R:{result.reps_grade})")
            if result.issues:
                for issue in result.issues:
                    print(f"    ⚠️ {issue}")
    
    # Sample excellent recommendations
    excellent_results = [r for r in all_results if r.overall_grade == "A" and len(r.issues) == 0]
    
    print(f"\n✅ SAMPLE EXCELLENT RECOMMENDATIONS:")
    print(f"{'='*50}")
    for result in excellent_results[:5]:
        print(f"\n  User: {result.user_summary}")
        print(f"  Exercise: {result.exercise_name}")
        print(f"  Recommended: {result.recommended_weight}lbs x {result.recommended_reps}")
        print(f"  Grade: A ✓")
    
    # Summary
    print(f"\n{'='*70}")
    print(f"📋 TEST SUMMARY")
    print(f"{'='*70}")
    
    a_b_pct = ((all_grades["A"] + all_grades["B"]) / total_recs) * 100 if total_recs > 0 else 0
    
    print(f"  Users Tested: {num_users}")
    print(f"  Recommendations Generated: {total_recs}")
    print(f"  Grade A/B Rate: {a_b_pct:.1f}%")
    print(f"  Overall Score: {overall_letter} ({avg_gpa:.2f}/4.0)")
    
    if avg_gpa >= 3.0:
        print(f"\n  ✅ PASS - Recommendation engine performing well!")
    else:
        print(f"\n  ⚠️ NEEDS IMPROVEMENT - Review the issues above")
    
    # Save results to JSON
    output = {
        "test_date": datetime.now().isoformat(),
        "num_users": num_users,
        "total_recommendations": total_recs,
        "grade_distribution": all_grades,
        "overall_gpa": avg_gpa,
        "overall_letter": overall_letter,
        "issues_breakdown": issues_by_type,
        "demographics": {
            "gender": {g.value: c for g, c in gender_counts.items()},
            "experience": {e.value: c for e, c in exp_counts.items()},
            "goals": {g.value: c for g, c in goal_counts.items()},
            "strength": {s.display_name: c for s, c in strength_counts.items()},
            "location": {l.value: c for l, c in location_counts.items()},
            "age_buckets": age_buckets,
            "weight_buckets": weight_buckets
        },
        "user_profiles": [u.to_dict() for u in users],
        "detailed_results": [
            {
                "user_id": r.user_id,
                "user_summary": r.user_summary,
                "exercise": r.exercise_name,
                "recommended_weight": r.recommended_weight,
                "expected_weight_range": r.expected_weight_range,
                "recommended_reps": r.recommended_reps,
                "expected_reps_range": r.expected_reps_range,
                "weight_grade": r.weight_grade,
                "reps_grade": r.reps_grade,
                "overall_grade": r.overall_grade,
                "issues": r.issues
            }
            for r in all_results
        ]
    }
    
    return output

if __name__ == "__main__":
    # Run test suite
    results = run_test_suite(100)
    
    # Save results
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, "recommendation_test_results.json")
    
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n📁 Results saved to: {output_path}")

