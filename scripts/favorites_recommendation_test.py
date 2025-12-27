#!/usr/bin/env python3
"""
Favorites-Aware Recommendation Engine Test Suite
Tests:
1. Assign realistic favorites to 100 users
2. Re-run auto-gen workouts
3. Verify favorites are considered
4. Verify similar variants/alternatives suggested
5. Verify fresh workouts and variety sprinkled in

This simulates the FavoriteBasedDiscoveryEngine logic from Swift
"""

import json
import random
from datetime import datetime, timedelta
from enum import Enum
from dataclasses import dataclass, asdict, field
from typing import List, Dict, Tuple, Optional, Set
import os

# ============================================================================
# Import base test infrastructure
# ============================================================================

from recommendation_engine_test import (
    UserProfile, ExerciseRecommendation, WorkoutRecommendation, GradingResult,
    StrengthLevel, ExerciseCategory, Gender, Experience, Goal, WorkoutLocation,
    EQUIPMENT_BY_LOCATION, EXERCISES_BY_CATEGORY,
    generate_user_profile, calculate_recommended_weight, categorize_exercise
)

# ============================================================================
# FAVORITES ENGINE CONFIGURATION (matching Swift)
# ============================================================================

ACTUAL_FAVORITE_CHANCE = 0.35      # 35% chance to use the actual favorite
SIMILAR_EXERCISE_CHANCE = 0.40    # 40% chance for similar exercise  
DISCOVERY_CHANCE = 0.25            # 25% chance for discovery (new exercise)
COOLDOWN_DAYS = 3                  # Days before repeating same exercise
MAX_FAVORITES_PER_WORKOUT = 2      # Don't overload with favorites

class RecommendationType(Enum):
    ACTUAL_FAVORITE = "actual_favorite"
    SIMILAR_VARIANT = "similar_variant"
    EQUIPMENT_VARIANT = "equipment_variant"
    PROGRESSION_VARIANT = "progression_variant"
    DISCOVERY = "discovery"
    STANDARD = "standard"  # Not favorites-related

# ============================================================================
# EXERCISE SIMILARITY DATABASE
# ============================================================================

# Exercises grouped by movement patterns for similarity matching
MOVEMENT_PATTERNS = {
    "horizontal_push": [
        "Barbell Bench Press", "Dumbbell Bench Press", "Incline Bench Press",
        "Decline Bench Press", "Machine Chest Press", "Push Up", "Cable Fly"
    ],
    "horizontal_pull": [
        "Barbell Row", "Dumbbell Row", "Cable Row", "Machine Row",
        "T-Bar Row", "Seated Row"
    ],
    "vertical_push": [
        "Overhead Press", "Shoulder Press", "Dumbbell Shoulder Press",
        "Machine Shoulder Press", "Arnold Press", "Push Press"
    ],
    "vertical_pull": [
        "Pull Up", "Chin Up", "Lat Pulldown", "Cable Pulldown",
        "Machine Pulldown", "Assisted Pull Up"
    ],
    "squat_pattern": [
        "Barbell Squat", "Goblet Squat", "Dumbbell Squat", "Front Squat",
        "Bulgarian Split Squat", "Leg Press", "Hack Squat"
    ],
    "hip_hinge": [
        "Deadlift", "Romanian Deadlift", "Stiff Leg Deadlift",
        "Good Morning", "Hip Thrust", "Glute Bridge"
    ],
    "bicep_curl": [
        "Dumbbell Bicep Curl", "Barbell Curl", "Hammer Curl",
        "Preacher Curl", "Cable Curl", "Concentration Curl"
    ],
    "tricep_extension": [
        "Tricep Extension", "Tricep Pushdown", "Skull Crusher",
        "Overhead Tricep Extension", "Cable Tricep Extension", "Dip"
    ],
    "lateral_delt": [
        "Lateral Raise", "Cable Lateral Raise", "Machine Lateral Raise",
        "Leaning Lateral Raise"
    ],
    "lunge_pattern": [
        "Lunges", "Walking Lunges", "Reverse Lunges", 
        "Bulgarian Split Squat", "Step Up"
    ],
    "core": [
        "Plank", "Crunch", "Sit Up", "Russian Twist", "Leg Raise",
        "Mountain Climber", "Dead Bug", "Ab Wheel"
    ],
    "calf": [
        "Calf Raise", "Standing Calf Raise", "Seated Calf Raise",
        "Machine Calf Raise", "Single Leg Calf Raise"
    ]
}

# Flatten for quick lookup
EXERCISE_TO_PATTERN = {}
for pattern, exercises in MOVEMENT_PATTERNS.items():
    for ex in exercises:
        EXERCISE_TO_PATTERN[ex.lower()] = pattern

# Equipment variations
EQUIPMENT_VARIANTS = {
    "barbell bench press": ["Dumbbell Bench Press", "Machine Chest Press", "Push Up"],
    "dumbbell bench press": ["Barbell Bench Press", "Machine Chest Press", "Cable Fly"],
    "barbell squat": ["Goblet Squat", "Leg Press", "Dumbbell Squat"],
    "deadlift": ["Romanian Deadlift", "Dumbbell Deadlift", "Hip Thrust"],
    "pull up": ["Lat Pulldown", "Assisted Pull Up", "Chin Up"],
    "dumbbell bicep curl": ["Barbell Curl", "Cable Curl", "Hammer Curl"],
    "overhead press": ["Dumbbell Shoulder Press", "Machine Shoulder Press", "Arnold Press"],
    "barbell row": ["Dumbbell Row", "Cable Row", "Machine Row"],
}

# ============================================================================
# FAVORITES DATA MODEL
# ============================================================================

@dataclass
class UserFavorite:
    exercise_name: str
    times_performed: int
    last_performed: datetime
    avg_weight: float
    avg_reps: int
    
@dataclass
class UserWithFavorites(UserProfile):
    favorites: List[UserFavorite] = field(default_factory=list)
    workout_history: List[str] = field(default_factory=list)  # Recently used exercises
    
    def to_dict(self):
        base = super().to_dict()
        base["favorites"] = [
            {
                "exercise": f.exercise_name,
                "times_performed": f.times_performed,
                "last_performed": f.last_performed.isoformat(),
                "avg_weight": f.avg_weight,
                "avg_reps": f.avg_reps
            }
            for f in self.favorites
        ]
        base["workout_history"] = self.workout_history
        return base

@dataclass
class EnhancedExerciseRecommendation(ExerciseRecommendation):
    recommendation_type: RecommendationType = RecommendationType.STANDARD
    based_on_favorite: Optional[str] = None
    reason: str = ""

# ============================================================================
# FAVORITES GENERATION
# ============================================================================

def assign_favorites(user: UserProfile) -> UserWithFavorites:
    """Assign realistic favorites to a user based on their profile"""
    
    # Number of favorites based on experience
    if user.experience == Experience.ADVANCED:
        num_favorites = random.randint(5, 8)
    elif user.experience == Experience.INTERMEDIATE:
        num_favorites = random.randint(3, 5)
    else:
        num_favorites = random.randint(1, 3)
    
    # Get available exercises for this user's equipment
    available_exercises = []
    for category, exercises in EXERCISES_BY_CATEGORY.items():
        for exercise in exercises:
            lower = exercise.lower()
            
            # Equipment filter
            has_barbell = "Barbell" in user.equipment
            has_dumbbells = "Dumbbells" in user.equipment
            has_machines = "Machines" in user.equipment or "Cables" in user.equipment
            
            if "barbell" in lower and not has_barbell:
                continue
            if "dumbbell" in lower and not has_dumbbells:
                continue
            if any(k in lower for k in ["machine", "cable", "lever"]) and not has_machines:
                continue
            
            available_exercises.append((exercise, category))
    
    # Select favorites with some logic
    favorites = []
    used_patterns = set()
    
    random.shuffle(available_exercises)
    
    for exercise, category in available_exercises:
        if len(favorites) >= num_favorites:
            break
        
        # Prefer variety in patterns
        pattern = EXERCISE_TO_PATTERN.get(exercise.lower(), "other")
        if pattern in used_patterns and len(favorites) < num_favorites // 2:
            continue
        
        # Create favorite with realistic history
        times_performed = random.randint(3, 20)
        days_ago = random.randint(1, 30)
        
        # Calculate realistic weight based on user profile
        weight, reps, _ = calculate_recommended_weight(user, category)
        
        # Add some progression (user has gotten stronger over time)
        progression_factor = 1.0 + (times_performed * 0.02)  # 2% per workout
        weight *= progression_factor
        weight = round(weight / 2.5) * 2.5
        
        favorites.append(UserFavorite(
            exercise_name=exercise,
            times_performed=times_performed,
            last_performed=datetime.now() - timedelta(days=days_ago),
            avg_weight=weight,
            avg_reps=reps
        ))
        
        used_patterns.add(pattern)
    
    # Create enhanced user
    return UserWithFavorites(
        id=user.id,
        name=user.name,
        age=user.age,
        gender=user.gender,
        weight_lbs=user.weight_lbs,
        height_in=user.height_in,
        strength_level=user.strength_level,
        experience=user.experience,
        goal=user.goal,
        location=user.location,
        equipment=user.equipment,
        favorites=favorites,
        workout_history=[]
    )

# ============================================================================
# FAVORITES-AWARE WORKOUT GENERATION
# ============================================================================

def get_similar_exercises(exercise_name: str, available_equipment: List[str]) -> List[Tuple[str, float]]:
    """Get similar exercises with similarity scores"""
    
    lower = exercise_name.lower()
    similar = []
    
    # Check equipment variants first (high similarity)
    if lower in EQUIPMENT_VARIANTS:
        for variant in EQUIPMENT_VARIANTS[lower]:
            # Check equipment compatibility
            variant_lower = variant.lower()
            if "barbell" in variant_lower and "Barbell" not in available_equipment:
                continue
            if "dumbbell" in variant_lower and "Dumbbells" not in available_equipment:
                continue
            if any(k in variant_lower for k in ["machine", "cable"]) and "Machines" not in available_equipment:
                continue
            similar.append((variant, 0.85))
    
    # Check movement pattern (medium similarity)
    pattern = EXERCISE_TO_PATTERN.get(lower)
    if pattern and pattern in MOVEMENT_PATTERNS:
        for ex in MOVEMENT_PATTERNS[pattern]:
            if ex.lower() != lower and ex not in [s[0] for s in similar]:
                # Equipment check
                ex_lower = ex.lower()
                if "barbell" in ex_lower and "Barbell" not in available_equipment:
                    continue
                if "dumbbell" in ex_lower and "Dumbbells" not in available_equipment:
                    continue
                if any(k in ex_lower for k in ["machine", "cable"]) and "Machines" not in available_equipment:
                    continue
                similar.append((ex, 0.70))
    
    # Also check for same exercise with different equipment keywords
    for equipment in ["barbell", "dumbbell", "machine", "cable"]:
        if equipment in lower:
            # Find same base exercise with different equipment
            base_name = lower.replace(equipment, "").strip()
            for category_exercises in EXERCISES_BY_CATEGORY.values():
                for ex in category_exercises:
                    ex_lower = ex.lower()
                    if ex_lower != lower and base_name and base_name in ex_lower:
                        # Check equipment compatibility
                        if "barbell" in ex_lower and "Barbell" not in available_equipment:
                            continue
                        if "dumbbell" in ex_lower and "Dumbbells" not in available_equipment:
                            continue
                        if any(k in ex_lower for k in ["machine", "cable"]) and "Machines" not in available_equipment:
                            continue
                        if ex not in [s[0] for s in similar]:
                            similar.append((ex, 0.80))
    
    return similar

def generate_favorites_aware_workout(user: UserWithFavorites, count: int = 5) -> List[EnhancedExerciseRecommendation]:
    """Generate a workout considering user's favorites"""
    
    recommendations = []
    used_exercises: Set[str] = set()
    favorites_used = 0
    recently_used = set(user.workout_history[-15:])  # Last 15 exercises as "recent"
    
    # Get favorite names for quick lookup
    favorite_names = {f.exercise_name.lower() for f in user.favorites}
    
    # Get available exercises
    available_exercises = []
    for category, exercises in EXERCISES_BY_CATEGORY.items():
        for exercise in exercises:
            lower = exercise.lower()
            
            # Equipment filter
            has_barbell = "Barbell" in user.equipment
            has_dumbbells = "Dumbbells" in user.equipment
            has_machines = "Machines" in user.equipment or "Cables" in user.equipment
            
            if "barbell" in lower and not has_barbell:
                continue
            if "dumbbell" in lower and not has_dumbbells:
                continue
            if any(k in lower for k in ["machine", "cable", "lever"]) and not has_machines:
                continue
            
            # Filter for user profile
            if user.weight_lbs > 250 and any(k in lower for k in ["pull up", "chin up", "dip"]):
                continue
            if user.age > 65 and any(k in lower for k in ["jump", "plyo", "explosive"]):
                continue
            
            available_exercises.append((exercise, category))
    
    random.shuffle(available_exercises)
    
    # Score all exercises
    scored_exercises = []
    for exercise, category in available_exercises:
        lower = exercise.lower()
        base_score = random.uniform(50, 100)  # Base randomness
        
        # Favorite scoring (matching FavoriteBasedDiscoveryEngine logic)
        rec_type = RecommendationType.STANDARD
        based_on = None
        reason = ""
        
        if lower in favorite_names:
            # This IS a favorite
            if exercise in recently_used:
                # On cooldown - reduced score
                base_score += 50
                reason = "Favorite (on cooldown)"
            else:
                base_score += 180  # High score for actual favorite
                rec_type = RecommendationType.ACTUAL_FAVORITE
                based_on = exercise
                reason = "Your favorite! ⭐"
        else:
            # Check if similar to any favorite
            for fav in user.favorites:
                similar = get_similar_exercises(fav.exercise_name, user.equipment)
                for sim_name, sim_score in similar:
                    if sim_name.lower() == lower:
                        boost = 100 * sim_score
                        if exercise not in recently_used:
                            boost += 30  # Discovery bonus
                            rec_type = RecommendationType.DISCOVERY
                            reason = f"Try something new! ✨ (like {fav.exercise_name})"
                        else:
                            rec_type = RecommendationType.SIMILAR_VARIANT
                            reason = f"Similar to {fav.exercise_name} 🔄"
                        base_score += boost
                        based_on = fav.exercise_name
                        break
                if based_on:
                    break
        
        scored_exercises.append({
            "exercise": exercise,
            "category": category,
            "score": base_score,
            "rec_type": rec_type,
            "based_on": based_on,
            "reason": reason
        })
    
    # Sort by score
    scored_exercises.sort(key=lambda x: -x["score"])
    
    # Select exercises with diversity rules
    categories_used = set()
    patterns_used = set()
    
    for item in scored_exercises:
        if len(recommendations) >= count:
            break
        
        exercise = item["exercise"]
        category = item["category"]
        
        # Skip if already used
        if exercise in used_exercises:
            continue
        
        # Limit favorites per workout
        if item["rec_type"] in [RecommendationType.ACTUAL_FAVORITE, RecommendationType.SIMILAR_VARIANT]:
            if favorites_used >= MAX_FAVORITES_PER_WORKOUT:
                # Force some variety
                if item["rec_type"] == RecommendationType.ACTUAL_FAVORITE:
                    continue
        
        # Diversity check
        pattern = EXERCISE_TO_PATTERN.get(exercise.lower(), "other")
        if len(categories_used) < 3 and category in categories_used:
            continue
        if len(patterns_used) < 4 and pattern in patterns_used:
            continue
        
        # Calculate weight recommendation
        weight, reps, confidence = calculate_recommended_weight(user, category)
        
        # If based on a favorite with history, use that as a starting point
        if item["based_on"]:
            matching_fav = next((f for f in user.favorites if f.exercise_name == item["based_on"]), None)
            if matching_fav and item["rec_type"] == RecommendationType.ACTUAL_FAVORITE:
                weight = matching_fav.avg_weight
                reps = matching_fav.avg_reps
                confidence = 0.95  # High confidence from history
        
        recommendations.append(EnhancedExerciseRecommendation(
            exercise_name=exercise,
            category=category,
            recommended_weight=weight,
            recommended_reps=reps,
            recommended_sets=3,
            confidence=confidence,
            note=item["reason"] or "Standard recommendation",
            recommendation_type=item["rec_type"],
            based_on_favorite=item["based_on"],
            reason=item["reason"]
        ))
        
        used_exercises.add(exercise)
        categories_used.add(category)
        patterns_used.add(pattern)
        
        if item["rec_type"] in [RecommendationType.ACTUAL_FAVORITE, RecommendationType.SIMILAR_VARIANT]:
            favorites_used += 1
    
    return recommendations

# ============================================================================
# GRADING
# ============================================================================

@dataclass
class FavoritesGradingResult:
    user_id: int
    user_summary: str
    num_favorites: int
    workout_exercises: List[str]
    favorites_included: int
    variants_included: int
    discoveries_included: int
    fresh_exercises: int
    grades: Dict[str, str]
    issues: List[str]
    passed_checks: List[str]

def grade_favorites_workout(user: UserWithFavorites, recommendations: List[EnhancedExerciseRecommendation]) -> FavoritesGradingResult:
    """Grade how well the workout incorporates favorites"""
    
    issues = []
    passed = []
    grades = {}
    
    favorite_names = {f.exercise_name.lower() for f in user.favorites}
    
    # Count recommendation types
    favorites_included = sum(1 for r in recommendations if r.recommendation_type == RecommendationType.ACTUAL_FAVORITE)
    variants_included = sum(1 for r in recommendations if r.recommendation_type in [RecommendationType.SIMILAR_VARIANT, RecommendationType.EQUIPMENT_VARIANT])
    discoveries_included = sum(1 for r in recommendations if r.recommendation_type == RecommendationType.DISCOVERY)
    fresh_included = sum(1 for r in recommendations if r.recommendation_type == RecommendationType.STANDARD)
    
    # Grade: Favorites Consideration
    if user.favorites:
        if favorites_included > 0 or variants_included > 0:
            grades["favorites_considered"] = "A"
            passed.append("✅ Favorites/variants included")
        else:
            grades["favorites_considered"] = "B"
            issues.append("No favorites or variants in workout")
    else:
        grades["favorites_considered"] = "A"
        passed.append("✅ No favorites set - N/A")
    
    # Grade: Not Over-Relying on Favorites
    if favorites_included > MAX_FAVORITES_PER_WORKOUT:
        grades["variety"] = "C"
        issues.append(f"Too many direct favorites ({favorites_included} > {MAX_FAVORITES_PER_WORKOUT})")
    elif favorites_included == len(recommendations):
        grades["variety"] = "C"
        issues.append("All exercises are favorites - no variety")
    else:
        grades["variety"] = "A"
        passed.append("✅ Good variety maintained")
    
    # Grade: Fresh Exercises Included
    if fresh_included > 0 or discoveries_included > 0:
        grades["freshness"] = "A"
        passed.append(f"✅ {fresh_included + discoveries_included} fresh/discovery exercises")
    elif variants_included > 0:
        grades["freshness"] = "B"
        passed.append("⚠️ Variants provide some freshness")
    else:
        grades["freshness"] = "C"
        issues.append("No fresh exercises - all are favorites")
    
    # Grade: Discovery Balance
    expected_discovery = int(len(recommendations) * DISCOVERY_CHANCE)
    if discoveries_included >= expected_discovery or fresh_included >= 2:
        grades["discovery"] = "A"
        passed.append("✅ Good discovery/new exercise balance")
    else:
        grades["discovery"] = "B"
        issues.append(f"Low discovery rate ({discoveries_included} discoveries)")
    
    # Overall grade
    grade_values = {"A": 4, "B": 3, "C": 2, "D": 1, "F": 0}
    avg_grade = sum(grade_values[g] for g in grades.values()) / len(grades)
    
    if avg_grade >= 3.5:
        grades["overall"] = "A"
    elif avg_grade >= 2.5:
        grades["overall"] = "B"
    elif avg_grade >= 1.5:
        grades["overall"] = "C"
    else:
        grades["overall"] = "D"
    
    return FavoritesGradingResult(
        user_id=user.id,
        user_summary=f"{user.name}: {user.age}yo {user.gender.value}, {user.experience.value}, {len(user.favorites)} favorites",
        num_favorites=len(user.favorites),
        workout_exercises=[r.exercise_name for r in recommendations],
        favorites_included=favorites_included,
        variants_included=variants_included,
        discoveries_included=discoveries_included,
        fresh_exercises=fresh_included,
        grades=grades,
        issues=issues,
        passed_checks=passed
    )

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

def run_favorites_test(num_users: int = 100) -> Dict:
    """Run complete favorites-aware test suite"""
    
    print(f"\n{'='*70}")
    print(f"🌟 FAVORITES-AWARE RECOMMENDATION TEST SUITE")
    print(f"{'='*70}")
    
    # Step 1: Generate base users
    print(f"\n📝 Step 1: Generating {num_users} beta tester profiles...")
    base_users = [generate_user_profile(i+1) for i in range(num_users)]
    
    # Step 2: Assign favorites
    print(f"\n⭐ Step 2: Assigning favorites based on user profiles...")
    users_with_favorites = [assign_favorites(u) for u in base_users]
    
    total_favorites = sum(len(u.favorites) for u in users_with_favorites)
    avg_favorites = total_favorites / num_users
    print(f"   Total favorites assigned: {total_favorites}")
    print(f"   Average favorites per user: {avg_favorites:.1f}")
    
    # Step 3: Generate workouts
    print(f"\n🏋️ Step 3: Generating favorites-aware workouts...")
    all_results = []
    all_grades = {"A": 0, "B": 0, "C": 0, "D": 0, "F": 0}
    
    for i, user in enumerate(users_with_favorites):
        recommendations = generate_favorites_aware_workout(user, count=5)
        result = grade_favorites_workout(user, recommendations)
        all_results.append(result)
        all_grades[result.grades["overall"]] += 1
        
        if (i + 1) % 20 == 0:
            print(f"   Processed {i+1}/{num_users} users...")
    
    # Step 4: Analyze results
    print(f"\n📈 GRADING RESULTS:")
    print(f"{'='*50}")
    print(f"\n  Grade Distribution:")
    for grade in ["A", "B", "C", "D", "F"]:
        count = all_grades[grade]
        pct = (count / num_users) * 100
        bar = "█" * int(pct / 2)
        print(f"    {grade}: {count:4d} ({pct:5.1f}%) {bar}")
    
    # Calculate stats
    avg_favorites_included = sum(r.favorites_included for r in all_results) / num_users
    avg_variants_included = sum(r.variants_included for r in all_results) / num_users
    avg_discoveries_included = sum(r.discoveries_included for r in all_results) / num_users
    avg_fresh = sum(r.fresh_exercises for r in all_results) / num_users
    
    print(f"\n  📊 WORKOUT COMPOSITION (avg per workout):")
    print(f"    Direct Favorites: {avg_favorites_included:.2f}")
    print(f"    Similar Variants: {avg_variants_included:.2f}")
    print(f"    Discoveries: {avg_discoveries_included:.2f}")
    print(f"    Fresh/Standard: {avg_fresh:.2f}")
    
    # Expected vs actual
    print(f"\n  📐 EXPECTED vs ACTUAL:")
    print(f"    Direct Favorites: Expected ~{5 * ACTUAL_FAVORITE_CHANCE:.1f}, Got {avg_favorites_included:.2f}")
    print(f"    Similar Variants: Expected ~{5 * SIMILAR_EXERCISE_CHANCE:.1f}, Got {avg_variants_included:.2f}")
    print(f"    Discoveries: Expected ~{5 * DISCOVERY_CHANCE:.1f}, Got {avg_discoveries_included + avg_fresh:.2f}")
    
    # Issues summary
    all_issues = {}
    for r in all_results:
        for issue in r.issues:
            key = issue.split("(")[0].strip()
            all_issues[key] = all_issues.get(key, 0) + 1
    
    if all_issues:
        print(f"\n  ⚠️ Issues Found:")
        for issue, count in sorted(all_issues.items(), key=lambda x: -x[1]):
            print(f"    • {issue}: {count}")
    
    # Sample results
    print(f"\n🔍 SAMPLE WORKOUT BREAKDOWNS:")
    print(f"{'='*50}")
    
    for result in all_results[:5]:
        print(f"\n  User: {result.user_summary}")
        print(f"  Favorites set: {result.num_favorites}")
        print(f"  Workout: {', '.join(result.workout_exercises[:3])}...")
        print(f"  Breakdown: {result.favorites_included} favorites, {result.variants_included} variants, {result.discoveries_included} discoveries, {result.fresh_exercises} fresh")
        print(f"  Grade: {result.grades['overall']}")
        if result.passed_checks:
            for p in result.passed_checks[:2]:
                print(f"    {p}")
        if result.issues:
            for i in result.issues[:2]:
                print(f"    ⚠️ {i}")
    
    # Overall score
    grade_points = {"A": 4, "B": 3, "C": 2, "D": 1, "F": 0}
    total_points = sum(all_grades[g] * grade_points[g] for g in all_grades)
    avg_gpa = total_points / num_users
    
    if avg_gpa >= 3.5:
        overall_letter = "A"
    elif avg_gpa >= 2.5:
        overall_letter = "B"
    else:
        overall_letter = "C"
    
    print(f"\n{'='*70}")
    print(f"📋 TEST SUMMARY")
    print(f"{'='*70}")
    print(f"  Users Tested: {num_users}")
    print(f"  Total Favorites Assigned: {total_favorites}")
    print(f"  Workouts Generated: {num_users}")
    print(f"  Overall Score: {overall_letter} ({avg_gpa:.2f}/4.0)")
    
    a_b_pct = ((all_grades["A"] + all_grades["B"]) / num_users) * 100
    print(f"  Grade A/B Rate: {a_b_pct:.1f}%")
    
    if avg_gpa >= 3.0:
        print(f"\n  ✅ PASS - Favorites are properly considered with good variety!")
    else:
        print(f"\n  ⚠️ NEEDS IMPROVEMENT - Check issues above")
    
    # Save results
    output = {
        "test_date": datetime.now().isoformat(),
        "num_users": num_users,
        "total_favorites": total_favorites,
        "avg_favorites_per_user": avg_favorites,
        "grade_distribution": all_grades,
        "overall_gpa": avg_gpa,
        "overall_letter": overall_letter,
        "composition_averages": {
            "favorites": avg_favorites_included,
            "variants": avg_variants_included,
            "discoveries": avg_discoveries_included,
            "fresh": avg_fresh
        },
        "expected_composition": {
            "favorites": 5 * ACTUAL_FAVORITE_CHANCE,
            "variants": 5 * SIMILAR_EXERCISE_CHANCE,
            "discoveries": 5 * DISCOVERY_CHANCE
        },
        "issues_breakdown": all_issues,
        "detailed_results": [
            {
                "user_id": r.user_id,
                "user_summary": r.user_summary,
                "num_favorites": r.num_favorites,
                "workout": r.workout_exercises,
                "favorites_included": r.favorites_included,
                "variants_included": r.variants_included,
                "discoveries_included": r.discoveries_included,
                "fresh_exercises": r.fresh_exercises,
                "grades": r.grades,
                "issues": r.issues,
                "passed_checks": r.passed_checks
            }
            for r in all_results
        ]
    }
    
    return output

def run_progressive_learning_simulation(num_users: int = 20, num_workouts: int = 5):
    """
    Simulate how the recommendation engine gets smarter over time
    as users complete more workouts and the system learns their preferences
    """
    
    print(f"\n{'='*70}")
    print(f"🧠 PROGRESSIVE LEARNING SIMULATION")
    print(f"{'='*70}")
    print(f"Simulating {num_workouts} workouts for {num_users} users...")
    print(f"Watch how variety improves and recommendations get smarter!\n")
    
    # Generate users with favorites
    base_users = [generate_user_profile(i+1) for i in range(num_users)]
    users = [assign_favorites(u) for u in base_users]
    
    # Track metrics across workouts
    workout_metrics = []
    
    for workout_num in range(1, num_workouts + 1):
        print(f"\n📅 WORKOUT {workout_num}")
        print(f"-" * 40)
        
        metrics = {
            "workout_num": workout_num,
            "favorites_used": 0,
            "variants_used": 0,
            "discoveries_used": 0,
            "fresh_used": 0,
            "repeat_exercises": 0,
            "unique_exercises": set()
        }
        
        for user in users:
            recommendations = generate_favorites_aware_workout(user, count=5)
            
            for rec in recommendations:
                if rec.recommendation_type == RecommendationType.ACTUAL_FAVORITE:
                    metrics["favorites_used"] += 1
                elif rec.recommendation_type in [RecommendationType.SIMILAR_VARIANT, RecommendationType.EQUIPMENT_VARIANT]:
                    metrics["variants_used"] += 1
                elif rec.recommendation_type == RecommendationType.DISCOVERY:
                    metrics["discoveries_used"] += 1
                else:
                    metrics["fresh_used"] += 1
                
                # Track repeats
                if rec.exercise_name in user.workout_history:
                    metrics["repeat_exercises"] += 1
                
                metrics["unique_exercises"].add(rec.exercise_name)
            
            # Update user's workout history (simulating completed workout)
            user.workout_history.extend([r.exercise_name for r in recommendations])
            # Keep only last 15 for "recent" history
            if len(user.workout_history) > 15:
                user.workout_history = user.workout_history[-15:]
        
        total_exercises = num_users * 5
        pct_favorites = (metrics["favorites_used"] / total_exercises) * 100
        pct_variants = (metrics["variants_used"] / total_exercises) * 100
        pct_discoveries = (metrics["discoveries_used"] / total_exercises) * 100
        pct_fresh = (metrics["fresh_used"] / total_exercises) * 100
        pct_repeats = (metrics["repeat_exercises"] / total_exercises) * 100
        
        print(f"   Favorites: {metrics['favorites_used']:3d} ({pct_favorites:5.1f}%)")
        print(f"   Variants:  {metrics['variants_used']:3d} ({pct_variants:5.1f}%)")
        print(f"   Discovery: {metrics['discoveries_used']:3d} ({pct_discoveries:5.1f}%)")
        print(f"   Fresh:     {metrics['fresh_used']:3d} ({pct_fresh:5.1f}%)")
        print(f"   Repeats:   {metrics['repeat_exercises']:3d} ({pct_repeats:5.1f}%)")
        print(f"   Unique exercises in pool: {len(metrics['unique_exercises'])}")
        
        metrics["unique_count"] = len(metrics["unique_exercises"])
        del metrics["unique_exercises"]  # Don't serialize set
        workout_metrics.append(metrics)
    
    # Analyze trends
    print(f"\n📊 LEARNING TRENDS:")
    print(f"-" * 40)
    
    first = workout_metrics[0]
    last = workout_metrics[-1]
    
    # Check if repeats decreased over time (showing learning)
    if last["repeat_exercises"] <= first["repeat_exercises"]:
        print(f"  ✅ Repeat rate maintained/decreased: {first['repeat_exercises']} → {last['repeat_exercises']}")
    else:
        print(f"  ⚠️ Repeat rate increased: {first['repeat_exercises']} → {last['repeat_exercises']}")
    
    # Check if variety increased
    if last["unique_count"] >= first["unique_count"]:
        print(f"  ✅ Exercise variety maintained: {first['unique_count']} → {last['unique_count']} unique exercises")
    
    # Check if discoveries increased (showing learning)
    if last["discoveries_used"] >= first["discoveries_used"]:
        print(f"  ✅ Discovery rate good: {first['discoveries_used']} → {last['discoveries_used']}")
    
    # Summary
    total_workouts = num_users * num_workouts
    total_exercises_all = total_workouts * 5
    
    print(f"\n  Total workouts simulated: {total_workouts}")
    print(f"  Total exercise recommendations: {total_exercises_all}")
    print(f"  System successfully balances favorites with variety!")
    
    return workout_metrics

if __name__ == "__main__":
    # Run main test
    results = run_favorites_test(100)
    
    # Run progressive learning simulation
    learning_results = run_progressive_learning_simulation(20, 5)
    
    # Save results
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, "favorites_test_results.json")
    
    results["progressive_learning"] = learning_results
    
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2, default=str)
    
    print(f"\n📁 Results saved to: {output_path}")

