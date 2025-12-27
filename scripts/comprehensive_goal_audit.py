#!/usr/bin/env python3
"""
Comprehensive Goal-Based Workout Audit
======================================
Creates 100 test users with varied profiles, generates 2 workouts each,
and produces a detailed accuracy scorecard comparing recommendations to user profiles.
"""

import random
import json
from datetime import datetime
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Set
import pandas as pd
from supabase import create_client

# Supabase credentials
SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

# ============================================================================
# DATA DEFINITIONS
# ============================================================================

GOALS = ["Build Muscle", "Get Lean", "Endurance", "General Fitness"]
EXPERIENCE_LEVELS = ["Beginner", "Intermediate", "Advanced"]
GENDERS = ["Male", "Female"]
LOCATIONS = ["Gym", "Home", "Outdoor"]
STRENGTH_LEVELS = ["Very Light", "Light", "Moderate", "Strong", "Very Strong"]

EQUIPMENT_BY_LOCATION = {
    "Gym": [
        ["Dumbbells", "Barbell", "Cables", "Machines", "Bench"],
        ["Dumbbells", "Cables", "Machines"],
        ["Barbell", "Machines", "Bench"],
        ["Dumbbells", "Barbell", "Cables", "Machines", "Bench", "Smith Machine", "Kettlebell"],
        ["Machines", "Cables", "Dumbbells"],
        ["Dumbbells", "Barbell", "Bench", "Pull-up Bar"]
    ],
    "Home": [
        ["Bodyweight"],
        ["Dumbbells", "Resistance Bands"],
        ["Dumbbells", "Kettlebell", "Resistance Bands"],
        ["Dumbbells", "Barbell", "Bench"],
        ["Bodyweight", "Resistance Bands", "Pull-up Bar"],
        ["Dumbbells", "Stability Ball"]
    ],
    "Outdoor": [
        ["Bodyweight"],
        ["Bodyweight", "Resistance Bands"],
        ["Bodyweight"]
    ]
}

INJURY_AREAS = ["Lower Back", "Shoulders", "Knees", "Wrists", "Neck", "Elbows", "Hips", "Ankles"]
ACCOMMODATION_LEVELS = ["avoid_completely", "light_only", "stretching_only", "be_careful"]

MUSCLE_GROUPS = [
    "Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms",
    "Quadriceps", "Hamstrings", "Glutes", "Calves",
    "Abs", "Obliques", "Lower Back"
]

WORKOUT_SPLITS = {
    "upper": ["Chest", "Back", "Shoulders", "Biceps", "Triceps"],
    "lower": ["Quadriceps", "Hamstrings", "Glutes", "Calves"],
    "push": ["Chest", "Shoulders", "Triceps"],
    "pull": ["Back", "Biceps", "Forearms"],
    "legs": ["Quadriceps", "Hamstrings", "Glutes", "Calves"],
    "core": ["Abs", "Obliques", "Lower Back"],
    "full_body": ["Chest", "Back", "Shoulders", "Quadriceps", "Glutes"]
}

# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class TestUser:
    id: int
    name: str
    age: int
    gender: str
    weight_lbs: float
    height_inches: int
    goal: str
    experience_level: str
    strength_level: str
    location: str
    equipment: List[str]
    injuries: List[Dict[str, str]]  # [{area: str, accommodation: str}]
    days_per_week: int

@dataclass
class Exercise:
    id: str
    name: str
    equipment: str
    primary_muscles: List[str]
    workout_type: str
    difficulty_level: int
    hypertrophy_rating: int
    strength_rating: int
    endurance_rating: int
    fat_loss_rating: int
    general_fitness_rating: int
    is_compound: bool
    supersetable: bool
    fatigability: int
    practicality_score: int

@dataclass
class WorkoutScorecard:
    equipment_score: float = 0.0
    safety_score: float = 0.0
    goal_alignment_score: float = 0.0
    experience_score: float = 0.0
    practicality_score: float = 0.0
    variety_score: float = 0.0
    
    equipment_issues: List[str] = field(default_factory=list)
    safety_issues: List[str] = field(default_factory=list)
    goal_issues: List[str] = field(default_factory=list)
    experience_issues: List[str] = field(default_factory=list)
    practicality_issues: List[str] = field(default_factory=list)
    variety_issues: List[str] = field(default_factory=list)
    
    @property
    def overall_score(self) -> float:
        weights = {
            'equipment': 0.25,
            'safety': 0.25,
            'goal_alignment': 0.20,
            'experience': 0.10,
            'practicality': 0.10,
            'variety': 0.10
        }
        return (
            self.equipment_score * weights['equipment'] +
            self.safety_score * weights['safety'] +
            self.goal_alignment_score * weights['goal_alignment'] +
            self.experience_score * weights['experience'] +
            self.practicality_score * weights['practicality'] +
            self.variety_score * weights['variety']
        )
    
    @property
    def passed(self) -> bool:
        return self.overall_score >= 75.0
    
    @property
    def all_issues(self) -> List[str]:
        return (self.equipment_issues + self.safety_issues + self.goal_issues + 
                self.experience_issues + self.practicality_issues + self.variety_issues)

@dataclass
class WorkoutResult:
    user: TestUser
    target_muscles: List[str]
    exercises: List[Exercise]
    scorecard: WorkoutScorecard

# ============================================================================
# TEST USER GENERATION
# ============================================================================

def generate_test_users(count: int = 100) -> List[TestUser]:
    """Generate diverse test users covering all filter combinations."""
    users = []
    
    first_names = [
        "Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Quinn", "Avery",
        "Cameron", "Skyler", "Dakota", "Jamie", "Reese", "Charlie", "Finley", "Sage",
        "Blake", "Drew", "Hayden", "Parker", "Rowan", "Spencer", "Sydney", "Phoenix",
        "River", "Addison", "Bailey", "Brooklyn", "Dallas", "Denver", "Eden", "Emerson",
        "Frankie", "Gray", "Harper", "Indigo", "Jesse", "Kendall", "Lane", "Marley",
        "Nico", "Ocean", "Peyton", "Reagan", "Sam", "Tatum", "Val", "Winter", "Xen", "Zion"
    ]
    
    for i in range(count):
        # Systematic distribution to cover all combinations
        goal = GOALS[i % len(GOALS)]
        level = EXPERIENCE_LEVELS[i % len(EXPERIENCE_LEVELS)]
        gender = GENDERS[i % len(GENDERS)]
        location = LOCATIONS[i % len(LOCATIONS)]
        strength = STRENGTH_LEVELS[i % len(STRENGTH_LEVELS)]
        
        # Age distribution: 18-70
        age_groups = [(18, 25), (26, 35), (36, 45), (46, 55), (56, 70)]
        age_range = age_groups[i % len(age_groups)]
        age = random.randint(age_range[0], age_range[1])
        
        # Weight based on gender and build
        if gender == "Male":
            weight = random.randint(140, 260)
        else:
            weight = random.randint(100, 200)
        
        # Height based on gender
        if gender == "Male":
            height = random.randint(64, 76)  # 5'4" to 6'4"
        else:
            height = random.randint(60, 72)  # 5'0" to 6'0"
        
        # Equipment based on location
        equip_options = EQUIPMENT_BY_LOCATION[location]
        equipment = equip_options[i % len(equip_options)]
        
        # Injuries: 30% of users have at least one
        injuries = []
        if i % 3 == 0:
            num_injuries = 2 if i % 10 == 0 else 1
            for j in range(num_injuries):
                area = INJURY_AREAS[(i + j) % len(INJURY_AREAS)]
                accommodation = ACCOMMODATION_LEVELS[(i + j) % len(ACCOMMODATION_LEVELS)]
                injuries.append({"area": area, "accommodation": accommodation})
        
        # Days per week
        days_options = [2, 3, 4, 5, 6]
        days = days_options[i % len(days_options)]
        
        user = TestUser(
            id=i + 1,
            name=f"{first_names[i % len(first_names)]} #{i + 1}",
            age=age,
            gender=gender,
            weight_lbs=weight,
            height_inches=height,
            goal=goal,
            experience_level=level,
            strength_level=strength,
            location=location,
            equipment=equipment,
            injuries=injuries,
            days_per_week=days
        )
        users.append(user)
    
    return users

# ============================================================================
# EXERCISE FETCHING & FILTERING
# ============================================================================

def fetch_exercises(supabase) -> List[Exercise]:
    """Fetch all exercises from Supabase."""
    print("📡 Fetching exercises from Supabase...")
    
    # Fetch in batches due to Supabase limits
    all_exercises = []
    offset = 0
    batch_size = 1000
    
    while True:
        result = supabase.table('exercises').select(
            'id, name, equipment, primary_muscles, workout_type, difficulty_level, '
            'hypertrophy_rating, strength_rating, endurance_rating, fat_loss_rating, '
            'general_fitness_rating, is_compound, supersetable, fatigability, practicality_score'
        ).range(offset, offset + batch_size - 1).execute()
        
        if not result.data:
            break
        
        for row in result.data:
            muscles = row.get('primary_muscles') or []
            if isinstance(muscles, str):
                try:
                    muscles = json.loads(muscles)
                except:
                    muscles = []
            
            exercise = Exercise(
                id=row['id'],
                name=row.get('name', 'Unknown'),
                equipment=row.get('equipment', 'Bodyweight') or 'Bodyweight',
                primary_muscles=muscles,
                workout_type=row.get('workout_type', 'Strength') or 'Strength',
                difficulty_level=row.get('difficulty_level', 2) or 2,
                hypertrophy_rating=row.get('hypertrophy_rating', 5) or 5,
                strength_rating=row.get('strength_rating', 5) or 5,
                endurance_rating=row.get('endurance_rating', 5) or 5,
                fat_loss_rating=row.get('fat_loss_rating', 5) or 5,
                general_fitness_rating=row.get('general_fitness_rating', 5) or 5,
                is_compound=row.get('is_compound', False) or False,
                supersetable=row.get('supersetable', True) if row.get('supersetable') is not None else True,
                fatigability=row.get('fatigability', 5) or 5,
                practicality_score=row.get('practicality_score', 50) or 50
            )
            all_exercises.append(exercise)
        
        offset += batch_size
        print(f"  Fetched {len(all_exercises)} exercises...")
        
        if len(result.data) < batch_size:
            break
    
    print(f"✅ Total exercises loaded: {len(all_exercises)}")
    return all_exercises

def normalize_equipment(equip: str) -> str:
    """Normalize equipment string for matching."""
    if not equip:
        return "bodyweight"
    equip = equip.lower().strip()
    
    # Normalize common variations
    mappings = {
        'dumbbell': 'dumbbells',
        'barbell': 'barbell',
        'cable': 'cables',
        'machine': 'machines',
        'band': 'resistance bands',
        'bands': 'resistance bands',
        'resistance band': 'resistance bands',
        'kettlebell': 'kettlebell',
        'bench': 'bench',
        'smith machine': 'smith machine',
        'pull-up bar': 'pull-up bar',
        'pullup bar': 'pull-up bar',
        'stability ball': 'stability ball',
        'medicine ball': 'medicine ball',
        'bodyweight': 'bodyweight',
        'body weight': 'bodyweight',
        'none': 'bodyweight'
    }
    
    for key, value in mappings.items():
        if key in equip:
            return value
    
    return equip

def filter_exercises_for_user(
    exercises: List[Exercise],
    user: TestUser,
    target_muscles: List[str]
) -> List[Exercise]:
    """Filter exercises based on user profile."""
    user_equipment = set(e.lower() for e in user.equipment)
    user_equipment.add('bodyweight')  # Everyone can do bodyweight
    
    # Get injury areas to avoid
    avoid_areas = set()
    light_only_areas = set()
    for injury in user.injuries:
        area = injury['area'].lower()
        if injury['accommodation'] == 'avoid_completely':
            avoid_areas.add(area)
        elif injury['accommodation'] == 'light_only':
            light_only_areas.add(area)
    
    # Map injury areas to muscles
    injury_muscle_map = {
        'lower back': ['lower back', 'erector spinae'],
        'shoulders': ['shoulders', 'deltoids', 'rotator cuff'],
        'knees': ['quadriceps', 'hamstrings'],
        'wrists': ['forearms', 'wrist'],
        'neck': ['neck', 'traps'],
        'elbows': ['biceps', 'triceps', 'forearms'],
        'hips': ['glutes', 'hip flexors', 'adductors'],
        'ankles': ['calves', 'tibialis']
    }
    
    muscles_to_avoid = set()
    muscles_light_only = set()
    for area in avoid_areas:
        muscles_to_avoid.update(m.lower() for m in injury_muscle_map.get(area, []))
    for area in light_only_areas:
        muscles_light_only.update(m.lower() for m in injury_muscle_map.get(area, []))
    
    filtered = []
    for exercise in exercises:
        # Check equipment match
        exercise_equip = normalize_equipment(exercise.equipment)
        if exercise_equip not in user_equipment and exercise_equip != 'bodyweight':
            continue
        
        # Check muscle targeting
        exercise_muscles = [m.lower() for m in exercise.primary_muscles]
        target_muscles_lower = [m.lower() for m in target_muscles]
        
        if not any(m in exercise_muscles or any(t in m for t in target_muscles_lower) 
                   for m in exercise_muscles for t in target_muscles_lower):
            # Check if at least one target muscle is hit
            has_target = False
            for tm in target_muscles_lower:
                for em in exercise_muscles:
                    if tm in em or em in tm:
                        has_target = True
                        break
                if has_target:
                    break
            if not has_target and exercise_muscles:
                continue
        
        # Check injury safety
        unsafe = False
        for em in exercise_muscles:
            if em in muscles_to_avoid:
                unsafe = True
                break
        if unsafe:
            continue
        
        # Check difficulty for experience level
        difficulty = exercise.difficulty_level
        if user.experience_level == "Beginner" and difficulty > 2:
            continue
        if user.experience_level == "Intermediate" and difficulty > 3:
            continue
        
        filtered.append(exercise)
    
    return filtered

def score_exercise_for_goal(exercise: Exercise, goal: str) -> float:
    """Score an exercise based on how well it matches the user's goal."""
    if goal == "Build Muscle":
        return exercise.hypertrophy_rating + (5 if exercise.is_compound else 0)
    elif goal == "Get Lean":
        return exercise.fat_loss_rating + (3 if exercise.supersetable else 0)
    elif goal == "Endurance":
        return exercise.endurance_rating + (3 if exercise.fatigability < 5 else 0)
    elif goal == "General Fitness":
        return exercise.general_fitness_rating
    return 5

def select_exercises(
    exercises: List[Exercise],
    user: TestUser,
    target_muscles: List[str],
    count: int = 6
) -> List[Exercise]:
    """Select the best exercises for the user."""
    if not exercises:
        return []
    
    # Score all exercises
    scored = []
    for exercise in exercises:
        score = score_exercise_for_goal(exercise, user.goal)
        score += exercise.practicality_score / 20  # 0-5 points from practicality
        scored.append((exercise, score))
    
    # Sort by score descending
    scored.sort(key=lambda x: x[1], reverse=True)
    
    # Select top exercises, ensuring variety
    selected = []
    used_names = set()
    
    for exercise, score in scored:
        if len(selected) >= count:
            break
        
        # Avoid duplicates by name prefix
        name_prefix = exercise.name[:20].lower()
        if name_prefix in used_names:
            continue
        
        selected.append(exercise)
        used_names.add(name_prefix)
    
    return selected

# ============================================================================
# SCORECARD GENERATION
# ============================================================================

def generate_scorecard(
    user: TestUser,
    exercises: List[Exercise],
    target_muscles: List[str]
) -> WorkoutScorecard:
    """Generate a comprehensive scorecard for the workout."""
    scorecard = WorkoutScorecard()
    
    if not exercises:
        scorecard.equipment_score = 0
        scorecard.equipment_issues.append("No exercises generated")
        return scorecard
    
    # ─────────────────────────────────────────────────────────────────────────
    # 1. EQUIPMENT SCORE (25%)
    # ─────────────────────────────────────────────────────────────────────────
    user_equipment = set(e.lower() for e in user.equipment)
    user_equipment.add('bodyweight')
    
    equipment_matches = 0
    for exercise in exercises:
        exercise_equip = normalize_equipment(exercise.equipment)
        if exercise_equip in user_equipment or exercise_equip == 'bodyweight':
            equipment_matches += 1
        else:
            scorecard.equipment_issues.append(
                f"❌ '{exercise.name}' requires '{exercise.equipment}' (user has: {', '.join(user.equipment)})"
            )
    
    scorecard.equipment_score = (equipment_matches / len(exercises)) * 100
    
    # ─────────────────────────────────────────────────────────────────────────
    # 2. SAFETY SCORE (25%)
    # ─────────────────────────────────────────────────────────────────────────
    injury_muscle_map = {
        'lower back': ['lower back', 'erector', 'spine', 'deadlift', 'good morning'],
        'shoulders': ['shoulder', 'deltoid', 'overhead', 'press', 'lateral raise'],
        'knees': ['squat', 'lunge', 'leg press', 'leg extension'],
        'wrists': ['wrist', 'curl', 'press'],
        'neck': ['neck', 'shrug', 'upright row'],
        'elbows': ['tricep', 'bicep', 'skull crusher', 'extension'],
        'hips': ['hip', 'squat', 'lunge', 'deadlift'],
        'ankles': ['calf', 'jump', 'run']
    }
    
    avoid_keywords = set()
    for injury in user.injuries:
        if injury['accommodation'] in ['avoid_completely', 'light_only']:
            area = injury['area'].lower()
            avoid_keywords.update(injury_muscle_map.get(area, []))
    
    safety_violations = 0
    for exercise in exercises:
        name_lower = exercise.name.lower()
        muscles_lower = [m.lower() for m in exercise.primary_muscles]
        
        for keyword in avoid_keywords:
            if keyword in name_lower or any(keyword in m for m in muscles_lower):
                safety_violations += 1
                injury_area = [inj['area'] for inj in user.injuries 
                              if keyword in injury_muscle_map.get(inj['area'].lower(), [])][0]
                scorecard.safety_issues.append(
                    f"⚠️ '{exercise.name}' may aggravate {injury_area} injury"
                )
                break
    
    scorecard.safety_score = max(0, 100 - (safety_violations / len(exercises)) * 100)
    
    # ─────────────────────────────────────────────────────────────────────────
    # 3. GOAL ALIGNMENT SCORE (20%)
    # ─────────────────────────────────────────────────────────────────────────
    goal_ratings = []
    for exercise in exercises:
        if user.goal == "Build Muscle":
            rating = exercise.hypertrophy_rating
            if rating < 6:
                scorecard.goal_issues.append(
                    f"📊 '{exercise.name}' has low hypertrophy rating ({rating}/10)"
                )
        elif user.goal == "Get Lean":
            rating = exercise.fat_loss_rating
            if rating < 6:
                scorecard.goal_issues.append(
                    f"📊 '{exercise.name}' has low fat loss rating ({rating}/10)"
                )
        elif user.goal == "Endurance":
            rating = exercise.endurance_rating
            if rating < 6:
                scorecard.goal_issues.append(
                    f"📊 '{exercise.name}' has low endurance rating ({rating}/10)"
                )
        else:  # General Fitness
            rating = exercise.general_fitness_rating
        
        goal_ratings.append(rating)
    
    avg_rating = sum(goal_ratings) / len(goal_ratings) if goal_ratings else 5
    scorecard.goal_alignment_score = (avg_rating / 10) * 100
    
    # Check compound exercise ratio for Build Muscle
    if user.goal == "Build Muscle":
        compound_count = sum(1 for e in exercises if e.is_compound)
        if compound_count < len(exercises) * 0.4:
            scorecard.goal_issues.append(
                f"💪 Only {compound_count}/{len(exercises)} exercises are compound (should be 40%+)"
            )
            scorecard.goal_alignment_score -= 10
    
    # Check supersetable ratio for Get Lean
    if user.goal == "Get Lean":
        superset_count = sum(1 for e in exercises if e.supersetable)
        if superset_count < len(exercises) * 0.6:
            scorecard.goal_issues.append(
                f"🔥 Only {superset_count}/{len(exercises)} exercises are supersetable (should be 60%+)"
            )
            scorecard.goal_alignment_score -= 10
    
    # ─────────────────────────────────────────────────────────────────────────
    # 4. EXPERIENCE SCORE (10%)
    # ─────────────────────────────────────────────────────────────────────────
    difficulty_issues = 0
    for exercise in exercises:
        difficulty = exercise.difficulty_level
        
        if user.experience_level == "Beginner":
            if difficulty > 2:
                difficulty_issues += 1
                scorecard.experience_issues.append(
                    f"📈 '{exercise.name}' too difficult for beginner (level {difficulty})"
                )
        elif user.experience_level == "Intermediate":
            if difficulty > 3:
                difficulty_issues += 1
                scorecard.experience_issues.append(
                    f"📈 '{exercise.name}' too difficult for intermediate (level {difficulty})"
                )
    
    scorecard.experience_score = max(0, 100 - (difficulty_issues / len(exercises)) * 100)
    
    # ─────────────────────────────────────────────────────────────────────────
    # 5. PRACTICALITY SCORE (10%)
    # ─────────────────────────────────────────────────────────────────────────
    practicality_scores = [e.practicality_score for e in exercises]
    avg_practicality = sum(practicality_scores) / len(practicality_scores) if practicality_scores else 50
    
    low_practicality = [e for e in exercises if e.practicality_score < 40]
    for e in low_practicality:
        scorecard.practicality_issues.append(
            f"🛠️ '{e.name}' has low practicality score ({e.practicality_score}/100)"
        )
    
    scorecard.practicality_score = avg_practicality
    
    # ─────────────────────────────────────────────────────────────────────────
    # 6. VARIETY SCORE (10%)
    # ─────────────────────────────────────────────────────────────────────────
    unique_equipment = set(normalize_equipment(e.equipment) for e in exercises)
    unique_muscles = set()
    for e in exercises:
        unique_muscles.update(m.lower() for m in e.primary_muscles)
    
    # Good variety = at least 2 equipment types and 3+ muscle groups
    variety_score = 0
    if len(unique_equipment) >= 2:
        variety_score += 50
    else:
        scorecard.variety_issues.append(
            f"🔄 Only {len(unique_equipment)} equipment type(s) used"
        )
    
    if len(unique_muscles) >= 3:
        variety_score += 50
    else:
        scorecard.variety_issues.append(
            f"🔄 Only {len(unique_muscles)} muscle group(s) targeted"
        )
    
    scorecard.variety_score = variety_score
    
    return scorecard

# ============================================================================
# WORKOUT GENERATION
# ============================================================================

def generate_workout(
    user: TestUser,
    all_exercises: List[Exercise],
    target_muscles: List[str]
) -> WorkoutResult:
    """Generate a workout for a user targeting specific muscles."""
    
    # Filter exercises for this user
    filtered = filter_exercises_for_user(all_exercises, user, target_muscles)
    
    # Select best exercises
    selected = select_exercises(filtered, user, target_muscles, count=6)
    
    # Generate scorecard
    scorecard = generate_scorecard(user, selected, target_muscles)
    
    return WorkoutResult(
        user=user,
        target_muscles=target_muscles,
        exercises=selected,
        scorecard=scorecard
    )

# ============================================================================
# REPORT GENERATION
# ============================================================================

def generate_report(results: List[WorkoutResult]) -> str:
    """Generate comprehensive audit report."""
    report = []
    
    # Header
    report.append("=" * 80)
    report.append("       COMPREHENSIVE GOAL-BASED WORKOUT AUDIT REPORT")
    report.append(f"       Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    report.append("=" * 80)
    report.append("")
    
    # Summary Statistics
    total_workouts = len(results)
    passed = sum(1 for r in results if r.scorecard.passed)
    failed = total_workouts - passed
    avg_score = sum(r.scorecard.overall_score for r in results) / total_workouts
    
    report.append("📊 SUMMARY STATISTICS")
    report.append("-" * 40)
    report.append(f"  Total Workouts Generated: {total_workouts}")
    report.append(f"  Passed (≥75%):           {passed} ({passed/total_workouts*100:.1f}%)")
    report.append(f"  Failed (<75%):           {failed} ({failed/total_workouts*100:.1f}%)")
    report.append(f"  Average Score:           {avg_score:.1f}%")
    report.append("")
    
    # Score Breakdown by Category
    report.append("📈 SCORE BREAKDOWN BY CATEGORY")
    report.append("-" * 40)
    
    categories = ['equipment', 'safety', 'goal_alignment', 'experience', 'practicality', 'variety']
    for cat in categories:
        scores = [getattr(r.scorecard, f"{cat}_score") for r in results]
        avg = sum(scores) / len(scores)
        min_score = min(scores)
        max_score = max(scores)
        report.append(f"  {cat.replace('_', ' ').title():20s}: Avg {avg:5.1f}%  (Min: {min_score:.0f}, Max: {max_score:.0f})")
    
    report.append("")
    
    # Score by Goal
    report.append("🎯 RESULTS BY GOAL")
    report.append("-" * 40)
    
    for goal in GOALS:
        goal_results = [r for r in results if r.user.goal == goal]
        if goal_results:
            avg = sum(r.scorecard.overall_score for r in goal_results) / len(goal_results)
            passed_count = sum(1 for r in goal_results if r.scorecard.passed)
            report.append(f"  {goal:20s}: Avg {avg:5.1f}%  ({passed_count}/{len(goal_results)} passed)")
    
    report.append("")
    
    # Score by Experience Level
    report.append("📚 RESULTS BY EXPERIENCE LEVEL")
    report.append("-" * 40)
    
    for level in EXPERIENCE_LEVELS:
        level_results = [r for r in results if r.user.experience_level == level]
        if level_results:
            avg = sum(r.scorecard.overall_score for r in level_results) / len(level_results)
            passed_count = sum(1 for r in level_results if r.scorecard.passed)
            report.append(f"  {level:20s}: Avg {avg:5.1f}%  ({passed_count}/{len(level_results)} passed)")
    
    report.append("")
    
    # Score by Location
    report.append("📍 RESULTS BY LOCATION")
    report.append("-" * 40)
    
    for location in LOCATIONS:
        loc_results = [r for r in results if r.user.location == location]
        if loc_results:
            avg = sum(r.scorecard.overall_score for r in loc_results) / len(loc_results)
            passed_count = sum(1 for r in loc_results if r.scorecard.passed)
            report.append(f"  {location:20s}: Avg {avg:5.1f}%  ({passed_count}/{len(loc_results)} passed)")
    
    report.append("")
    
    # Most Common Issues
    report.append("⚠️ MOST COMMON ISSUES")
    report.append("-" * 40)
    
    all_issues = []
    for r in results:
        all_issues.extend(r.scorecard.all_issues)
    
    issue_counts = {}
    for issue in all_issues:
        # Generalize issue
        if "requires '" in issue:
            key = "Equipment mismatch"
        elif "injury" in issue.lower() or "aggravate" in issue.lower():
            key = "Safety/injury concern"
        elif "rating" in issue.lower():
            key = "Low goal rating"
        elif "difficult" in issue.lower():
            key = "Difficulty mismatch"
        elif "practicality" in issue.lower():
            key = "Low practicality"
        elif "equipment type" in issue.lower() or "muscle group" in issue.lower():
            key = "Low variety"
        else:
            key = "Other"
        
        issue_counts[key] = issue_counts.get(key, 0) + 1
    
    for issue_type, count in sorted(issue_counts.items(), key=lambda x: -x[1])[:10]:
        report.append(f"  {count:4d}x  {issue_type}")
    
    report.append("")
    
    # Detailed User Audits (20 users)
    report.append("=" * 80)
    report.append("       DETAILED USER AUDITS (20 Sample Users)")
    report.append("=" * 80)
    report.append("")
    
    # Select 20 diverse users: 5 best, 5 worst, 10 random
    sorted_results = sorted(results, key=lambda r: r.scorecard.overall_score)
    worst_5 = sorted_results[:5]
    best_5 = sorted_results[-5:]
    middle = sorted_results[5:-5]
    random_10 = random.sample(middle, min(10, len(middle)))
    
    sample_results = worst_5 + random_10 + best_5
    
    for i, result in enumerate(sample_results, 1):
        user = result.user
        sc = result.scorecard
        
        status = "✅ PASSED" if sc.passed else "❌ FAILED"
        
        report.append(f"┌{'─' * 78}┐")
        report.append(f"│ USER #{user.id}: {user.name[:30]:30s}  {status:12s}  Score: {sc.overall_score:5.1f}% │")
        report.append(f"├{'─' * 78}┤")
        
        # User profile
        report.append(f"│ Profile:                                                                     │")
        report.append(f"│   Age: {user.age}, Gender: {user.gender}, Weight: {user.weight_lbs}lbs, Height: {user.height_inches}\"         │")
        report.append(f"│   Goal: {user.goal:20s}  Experience: {user.experience_level:15s}        │")
        report.append(f"│   Location: {user.location:10s}  Equipment: {', '.join(user.equipment)[:40]:40s}│")
        
        if user.injuries:
            injuries_str = ", ".join([f"{inj['area']} ({inj['accommodation']})" for inj in user.injuries])
            report.append(f"│   Injuries: {injuries_str[:60]:60s}      │")
        else:
            report.append(f"│   Injuries: None                                                             │")
        
        report.append(f"├{'─' * 78}┤")
        
        # Target muscles and exercises
        report.append(f"│ Target Muscles: {', '.join(result.target_muscles)[:60]:60s}│")
        report.append(f"│                                                                              │")
        report.append(f"│ Exercises Generated:                                                         │")
        
        for j, exercise in enumerate(result.exercises[:6], 1):
            name = exercise.name[:40]
            equip = exercise.equipment[:15]
            goal_rating = 0
            if user.goal == "Build Muscle":
                goal_rating = exercise.hypertrophy_rating
            elif user.goal == "Get Lean":
                goal_rating = exercise.fat_loss_rating
            elif user.goal == "Endurance":
                goal_rating = exercise.endurance_rating
            else:
                goal_rating = exercise.general_fitness_rating
            
            report.append(f"│   {j}. {name:40s} [{equip:15s}] Rating:{goal_rating:2d}/10│")
        
        if len(result.exercises) < 6:
            for _ in range(6 - len(result.exercises)):
                report.append(f"│   -. (no exercise)                                                          │")
        
        report.append(f"├{'─' * 78}┤")
        
        # Scores
        report.append(f"│ Scorecard:                                                                   │")
        report.append(f"│   Equipment: {sc.equipment_score:5.1f}%  Safety: {sc.safety_score:5.1f}%  Goal: {sc.goal_alignment_score:5.1f}%  Exp: {sc.experience_score:5.1f}%│")
        report.append(f"│   Practicality: {sc.practicality_score:5.1f}%  Variety: {sc.variety_score:5.1f}%            OVERALL: {sc.overall_score:5.1f}%│")
        
        # Issues
        if sc.all_issues:
            report.append(f"├{'─' * 78}┤")
            report.append(f"│ Issues Found:                                                                │")
            for issue in sc.all_issues[:5]:
                issue_short = issue[:72]
                report.append(f"│   • {issue_short:72s}│")
            if len(sc.all_issues) > 5:
                report.append(f"│   ... and {len(sc.all_issues) - 5} more issues                                                  │")
        
        report.append(f"└{'─' * 78}┘")
        report.append("")
    
    # Footer
    report.append("=" * 80)
    report.append("                          END OF AUDIT REPORT")
    report.append("=" * 80)
    
    return "\n".join(report)

# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    print("╔══════════════════════════════════════════════════════════════════════════════╗")
    print("║           🧪 COMPREHENSIVE GOAL-BASED WORKOUT AUDIT                          ║")
    print("║           100 Users × 2 Workouts Each = 200 Workouts                         ║")
    print("╚══════════════════════════════════════════════════════════════════════════════╝")
    print()
    
    # Connect to Supabase
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    # Fetch exercises
    all_exercises = fetch_exercises(supabase)
    
    if not all_exercises:
        print("❌ No exercises found in database!")
        return
    
    # Generate test users
    print("\n👥 Generating 100 test users...")
    test_users = generate_test_users(100)
    print(f"✅ Generated {len(test_users)} diverse test users")
    
    # Show user distribution
    print("\n📊 User Distribution:")
    for goal in GOALS:
        count = sum(1 for u in test_users if u.goal == goal)
        print(f"   {goal}: {count}")
    
    # Generate workouts (2 per user)
    print("\n🏋️ Generating workouts...")
    all_results = []
    
    workout_splits = [
        ("Upper Body", ["Chest", "Back", "Shoulders", "Biceps", "Triceps"]),
        ("Lower Body", ["Quadriceps", "Hamstrings", "Glutes", "Calves"])
    ]
    
    for i, user in enumerate(test_users):
        if (i + 1) % 20 == 0:
            print(f"   Processing user {i + 1}/100...")
        
        for split_name, muscles in workout_splits:
            result = generate_workout(user, all_exercises, muscles)
            all_results.append(result)
    
    print(f"✅ Generated {len(all_results)} workouts")
    
    # Generate report
    print("\n📝 Generating detailed report...")
    report = generate_report(all_results)
    
    # Save report
    report_path = "/Users/josephreed/Desktop/Workout App/GOAL_AUDIT_REPORT.txt"
    with open(report_path, 'w') as f:
        f.write(report)
    
    print(f"✅ Report saved to: {report_path}")
    
    # Print summary to console
    print("\n" + "=" * 60)
    print("QUICK SUMMARY")
    print("=" * 60)
    
    total = len(all_results)
    passed = sum(1 for r in all_results if r.scorecard.passed)
    avg = sum(r.scorecard.overall_score for r in all_results) / total
    
    print(f"  Total Workouts:    {total}")
    print(f"  Passed (≥75%):     {passed} ({passed/total*100:.1f}%)")
    print(f"  Failed (<75%):     {total - passed} ({(total-passed)/total*100:.1f}%)")
    print(f"  Average Score:     {avg:.1f}%")
    print()
    
    # Print first part of report
    print("\n📄 First 100 lines of report:")
    print("-" * 60)
    for line in report.split('\n')[:100]:
        print(line)
    print("\n... [See full report in GOAL_AUDIT_REPORT.txt]")

if __name__ == "__main__":
    main()

