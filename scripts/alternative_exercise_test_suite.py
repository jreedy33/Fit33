#!/usr/bin/env python3
"""
Alternative/Similar Exercise Test Suite
Tests if exercise swap suggestions are appropriate matches
"""

import json
import random
from datetime import datetime
from supabase import create_client
from collections import Counter, defaultdict

# Supabase credentials
SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ============================================================================
# SIMILARITY RULES
# ============================================================================

# Movement pattern keywords for grouping - MORE COMPREHENSIVE
MOVEMENT_PATTERNS = {
    "push_horizontal": ["bench press", "push up", "pushup", "chest press", "fly", "pec", "floor press", "dip"],
    "push_vertical": ["shoulder press", "overhead press", "military press", "pike push", "arnold press", "z press"],
    "pull_horizontal": ["row", "seated row", "bent over row", "cable row", "t-bar", "pendlay"],
    "pull_vertical": ["pull up", "pullup", "chin up", "chinup", "lat pulldown", "pulldown", "pull down"],
    "hip_hinge": ["deadlift", "romanian", "good morning", "hip hinge", "hyperextension", "back extension", "hip thrust", "bridge", "glute bridge"],
    "squat": ["squat", "leg press", "hack squat", "goblet", "front squat", "back squat", "sissy squat"],
    "lunge": ["lunge", "split squat", "step up", "bulgarian", "curtsy", "walking lunge"],
    "curl": ["curl", "bicep", "hammer curl", "preacher", "concentration", "incline curl"],
    "extension": ["extension", "tricep", "pushdown", "skull crusher", "kickback", "dip", "close grip"],
    "raise": ["raise", "lateral raise", "front raise", "rear delt", "upright row", "shrug", "calf raise"],
    "crunch": ["crunch", "sit up", "situp", "v-up", "leg raise", "knee raise", "tuck"],
    "plank": ["plank", "hold", "isometric", "dead bug", "bird dog", "hollow"],
    "rotation": ["rotation", "twist", "woodchop", "russian twist", "cable twist"],
    "stretch": ["stretch", "yoga", "mobility", "flexibility", "pigeon", "child pose"],
}

# Equipment substitution groups (similar equipment types)
EQUIPMENT_GROUPS = {
    "free_weights": ["barbell", "dumbbell", "ez bar", "kettlebell"],
    "machines": ["machine", "lever", "cable"],
    "bodyweight": ["bodyweight", ""],
    "bands": ["resistance band", "band"],
}

# Muscle group relationships (which muscles work together)
MUSCLE_RELATIONSHIPS = {
    "chest": ["chest", "upper chest", "lower chest", "pecs", "pectorals"],
    "back": ["back", "lats", "upper back", "lower back", "traps", "rhomboids", "mid back"],
    "shoulders": ["shoulders", "front delts", "rear delts", "side delts", "delts", "deltoids", "rotator cuff"],
    "arms": ["biceps", "triceps", "forearms", "arms", "brachialis"],
    "legs": ["quads", "hamstrings", "glutes", "calves", "legs", "thighs", "adductors", "abductors", "hips", "hip flexors"],
    "core": ["abs", "obliques", "core", "lower abs", "transverse", "serratus"],
    "full_body": ["full body", "total body", "compound"],
    "neck": ["neck", "traps", "upper traps"],
}

# ============================================================================
# SIMILARITY SCORING
# ============================================================================

def get_muscle_group(muscles):
    """Get the main muscle group for a list of muscles"""
    if not muscles:
        return None
    if isinstance(muscles, str):
        muscles = [muscles]
    
    muscle_lower = [m.lower() for m in muscles if m]
    
    for group, members in MUSCLE_RELATIONSHIPS.items():
        if any(m in member or member in m for m in muscle_lower for member in members):
            return group
    
    return muscle_lower[0] if muscle_lower else None


def get_movement_pattern(name):
    """Identify the movement pattern of an exercise"""
    name_lower = name.lower()
    
    for pattern, keywords in MOVEMENT_PATTERNS.items():
        if any(kw in name_lower for kw in keywords):
            return pattern
    
    return "other"


def get_equipment_group(equipment):
    """Get the equipment group for an exercise"""
    if not equipment:
        return "bodyweight"
    
    equip_lower = equipment.lower()
    
    for group, members in EQUIPMENT_GROUPS.items():
        if any(m in equip_lower for m in members):
            return group
    
    return "other"


def calculate_similarity_score(original, alternative):
    """
    Calculate how similar two exercises are (0-100).
    PRIORITY: Muscle Match > Movement Pattern > Equipment
    A good alternative should hit the SAME MUSCLES with a SIMILAR MOVEMENT
    """
    score = 0
    reasons = []
    
    orig_name = (original.get('name') or '').lower()
    alt_name = (alternative.get('name') or '').lower()
    
    # Don't match with itself
    if orig_name == alt_name:
        return 0, ["Same exercise"]
    
    # 1. PRIMARY MUSCLE MATCH (50 points) - MOST IMPORTANT
    # An alternative MUST target the same muscle group
    orig_muscles = original.get('primary_muscles', [])
    alt_muscles = alternative.get('primary_muscles', [])
    
    if isinstance(orig_muscles, str):
        orig_muscles = [orig_muscles]
    if isinstance(alt_muscles, str):
        alt_muscles = [alt_muscles]
    
    orig_group = get_muscle_group(orig_muscles)
    alt_group = get_muscle_group(alt_muscles)
    
    muscle_match = False
    if orig_group and alt_group:
        if orig_group == alt_group:
            score += 50
            reasons.append(f"Same muscle group: {orig_group}")
            muscle_match = True
        else:
            # Check direct muscle match even if groups differ
            orig_muscles_lower = [m.lower() for m in orig_muscles if m]
            alt_muscles_lower = [m.lower() for m in alt_muscles if m]
            
            if any(om == am or om in am or am in om 
                   for om in orig_muscles_lower for am in alt_muscles_lower):
                score += 40
                reasons.append(f"Same primary muscle")
                muscle_match = True
    
    # If no muscle match at all, this is a poor alternative
    if not muscle_match:
        return score, reasons  # Return early with low score
    
    # 2. MOVEMENT PATTERN MATCH (30 points)
    orig_pattern = get_movement_pattern(original.get('name', ''))
    alt_pattern = get_movement_pattern(alternative.get('name', ''))
    
    if orig_pattern == alt_pattern and orig_pattern != "other":
        score += 30
        reasons.append(f"Same movement: {orig_pattern}")
    elif orig_pattern != "other" and alt_pattern != "other":
        # Related patterns
        push_patterns = {"push_horizontal", "push_vertical", "extension"}
        pull_patterns = {"pull_horizontal", "pull_vertical", "curl"}
        leg_patterns = {"squat", "lunge", "hip_hinge"}
        core_patterns = {"crunch", "plank", "rotation"}
        
        if (orig_pattern in push_patterns and alt_pattern in push_patterns) or \
           (orig_pattern in pull_patterns and alt_pattern in pull_patterns) or \
           (orig_pattern in leg_patterns and alt_pattern in leg_patterns) or \
           (orig_pattern in core_patterns and alt_pattern in core_patterns):
            score += 20
            reasons.append(f"Related movement")
    elif orig_pattern == "other" or alt_pattern == "other":
        # One or both don't have clear pattern - give partial credit
        score += 10
    
    # 3. EQUIPMENT - Now less important (15 points)
    # User can always substitute equipment for same muscle/movement
    orig_equip = get_equipment_group(original.get('equipment'))
    alt_equip = get_equipment_group(alternative.get('equipment'))
    
    if orig_equip == alt_equip:
        score += 15
        reasons.append(f"Same equipment")
    elif {orig_equip, alt_equip} <= {"free_weights", "machines", "bands"}:
        # All gym equipment is somewhat interchangeable
        score += 10
        reasons.append(f"Compatible equipment")
    elif "bodyweight" in {orig_equip, alt_equip}:
        # Bodyweight can substitute for anything (easier/harder variation)
        score += 5
        reasons.append(f"Bodyweight variation available")
    
    # 4. WORKOUT TYPE MATCH (5 points)
    orig_type = (original.get('workout_type') or '').lower()
    alt_type = (alternative.get('workout_type') or '').lower()
    
    if orig_type and alt_type and orig_type == alt_type:
        score += 5
        reasons.append(f"Same type: {orig_type}")
    
    return score, reasons


def find_alternatives(original, all_exercises, user_equipment=None, count=5):
    """
    Find the best alternative exercises for a given exercise.
    SMART LOGIC: 
    - Prioritize exercises user can do with their equipment
    - But ALSO include bodyweight alternatives (always available as fallback)
    - Filter by MUSCLE MATCH first (most important)
    """
    scored_alternatives = []
    
    # Get original exercise's muscle group for pre-filtering
    orig_muscles = original.get('primary_muscles', [])
    if isinstance(orig_muscles, str):
        orig_muscles = [orig_muscles]
    orig_group = get_muscle_group(orig_muscles)
    
    for alt in all_exercises:
        # Skip same exercise
        if alt.get('name') == original.get('name'):
            continue
        
        # PRE-FILTER: Must be in same muscle group (or related)
        alt_muscles = alt.get('primary_muscles', [])
        if isinstance(alt_muscles, str):
            alt_muscles = [alt_muscles]
        alt_group = get_muscle_group(alt_muscles)
        
        # Skip if completely different muscle group
        if orig_group and alt_group and orig_group != alt_group:
            # Check if direct muscle overlap
            orig_lower = [m.lower() for m in orig_muscles if m]
            alt_lower = [m.lower() for m in alt_muscles if m]
            if not any(o in a or a in o for o in orig_lower for a in alt_lower):
                continue
        
        # Equipment scoring (not filtering - we'll score it instead)
        equipment_bonus = 0
        if user_equipment:
            alt_equip = (alt.get('equipment') or '').lower()
            equip_parts = [p.strip() for p in alt_equip.split(',') if p.strip()]
            is_bodyweight = not equip_parts or equip_parts == ['bodyweight'] or alt_equip == 'bodyweight'
            
            user_equip_lower = [e.lower() for e in user_equipment]
            
            if is_bodyweight:
                # Bodyweight is always available - small bonus
                equipment_bonus = 5
            else:
                # Check if user has the equipment
                has_equipment = any(
                    ue in part or part in ue 
                    for part in equip_parts 
                    for ue in user_equip_lower
                )
                if has_equipment:
                    equipment_bonus = 20  # User can do this exercise!
                else:
                    equipment_bonus = -10  # User doesn't have equipment
        
        score, reasons = calculate_similarity_score(original, alt)
        
        # Add equipment bonus to score
        score += equipment_bonus
        if equipment_bonus == 20:
            reasons.append("User has equipment")
        elif equipment_bonus == -10:
            reasons.append("Equipment not available")
        
        if score > 20:  # Minimum threshold for a reasonable alternative
            scored_alternatives.append({
                'exercise': alt,
                'score': score,
                'reasons': reasons
            })
    
    # Sort by score descending
    scored_alternatives.sort(key=lambda x: -x['score'])
    
    return scored_alternatives[:count]


# ============================================================================
# GRADING
# ============================================================================

def grade_alternative(original, alternative):
    """
    Grade a single alternative suggestion.
    PRIORITY: Muscle > Movement > Equipment (equipment is flexible)
    Returns (score, issues)
    """
    issues = []
    score = 0
    
    orig_name = original.get('name', '')
    alt_name = alternative.get('name', '')
    
    # 1. MUSCLE MATCH (50 points) - CRITICAL
    orig_muscles = original.get('primary_muscles', [])
    alt_muscles = alternative.get('primary_muscles', [])
    
    if isinstance(orig_muscles, str):
        orig_muscles = [orig_muscles]
    if isinstance(alt_muscles, str):
        alt_muscles = [alt_muscles]
    
    orig_group = get_muscle_group(orig_muscles)
    alt_group = get_muscle_group(alt_muscles)
    
    if orig_group == alt_group:
        score += 50
    elif orig_group and alt_group:
        # Check direct muscle match
        orig_lower = [m.lower() for m in orig_muscles if m]
        alt_lower = [m.lower() for m in alt_muscles if m]
        
        if any(o == a or o in a or a in o for o in orig_lower for a in alt_lower):
            score += 40
        else:
            # Same body region?
            upper_body = {"chest", "back", "shoulders", "arms"}
            lower_body = {"legs", "full_body"}
            core_muscles = {"core", "neck"}
            
            if (orig_group in upper_body and alt_group in upper_body) or \
               (orig_group in lower_body and alt_group in lower_body) or \
               (orig_group in core_muscles and alt_group in core_muscles):
                score += 25
                issues.append(f"Different muscle but same region")
            else:
                issues.append(f"Different body region: {orig_group} vs {alt_group}")
    
    # 2. MOVEMENT PATTERN (30 points)
    orig_pattern = get_movement_pattern(orig_name)
    alt_pattern = get_movement_pattern(alt_name)
    
    if orig_pattern == alt_pattern and orig_pattern != "other":
        score += 30
    else:
        push_patterns = {"push_horizontal", "push_vertical", "extension"}
        pull_patterns = {"pull_horizontal", "pull_vertical", "curl"}
        leg_patterns = {"squat", "lunge", "hip_hinge"}
        core_patterns = {"crunch", "plank", "rotation"}
        stretch_patterns = {"stretch"}
        
        if (orig_pattern in push_patterns and alt_pattern in push_patterns) or \
           (orig_pattern in pull_patterns and alt_pattern in pull_patterns) or \
           (orig_pattern in leg_patterns and alt_pattern in leg_patterns) or \
           (orig_pattern in core_patterns and alt_pattern in core_patterns) or \
           (orig_pattern in stretch_patterns and alt_pattern in stretch_patterns):
            score += 20
        elif orig_pattern == "other" or alt_pattern == "other":
            score += 10  # Partial credit for unclear patterns
        else:
            issues.append(f"Different movement: {orig_pattern} vs {alt_pattern}")
    
    # 3. EQUIPMENT - Less important (15 points)
    # Equipment can always be substituted
    orig_equip = get_equipment_group(original.get('equipment'))
    alt_equip = get_equipment_group(alternative.get('equipment'))
    
    if orig_equip == alt_equip:
        score += 15
    elif {orig_equip, alt_equip} <= {"free_weights", "machines", "bands", "bodyweight"}:
        score += 10  # All somewhat interchangeable
    else:
        score += 5  # Still give some credit - equipment is flexible
    
    # 4. WORKOUT TYPE (5 points)
    if original.get('workout_type') == alternative.get('workout_type'):
        score += 5
    
    return score, issues


def grade_alternatives(original, alternatives):
    """
    Grade a list of alternative suggestions.
    """
    if not alternatives:
        return 0, ["No alternatives found"]
    
    total_score = 0
    all_issues = []
    
    for alt in alternatives:
        alt_ex = alt['exercise'] if isinstance(alt, dict) and 'exercise' in alt else alt
        score, issues = grade_alternative(original, alt_ex)
        total_score += score
        all_issues.extend(issues)
    
    avg_score = total_score / len(alternatives)
    return avg_score, all_issues[:5]  # Limit issues


# ============================================================================
# TEST RUNNER
# ============================================================================

def run_test_case(test_id, original_exercise, all_exercises, user_equipment):
    """
    Run a single test case for alternative exercises.
    """
    # Find alternatives
    alternatives = find_alternatives(original_exercise, all_exercises, user_equipment, count=5)
    
    # Grade the alternatives
    avg_score, issues = grade_alternatives(original_exercise, alternatives)
    
    # Determine grade
    if avg_score >= 80:
        grade = 'A'
    elif avg_score >= 65:
        grade = 'B'
    elif avg_score >= 50:
        grade = 'C'
    elif avg_score >= 35:
        grade = 'D'
    else:
        grade = 'F'
    
    return {
        "test_id": test_id,
        "original_exercise": {
            "name": original_exercise.get('name'),
            "equipment": original_exercise.get('equipment'),
            "muscles": original_exercise.get('primary_muscles'),
            "movement_pattern": get_movement_pattern(original_exercise.get('name', '')),
        },
        "user_equipment": user_equipment,
        "alternatives_found": len(alternatives),
        "alternatives": [
            {
                "name": alt['exercise'].get('name'),
                "equipment": alt['exercise'].get('equipment'),
                "muscles": alt['exercise'].get('primary_muscles'),
                "similarity_score": alt['score'],
                "reasons": alt['reasons']
            }
            for alt in alternatives
        ],
        "avg_score": round(avg_score, 1),
        "issues": issues,
        "grade": grade
    }


def main():
    print("=" * 90)
    print("🔄 ALTERNATIVE EXERCISE TEST SUITE")
    print("   Testing exercise swap/shuffle suggestions")
    print("=" * 90)
    print()
    
    # Fetch exercises
    print("📥 Fetching exercises...")
    all_exercises = []
    offset = 0
    while True:
        response = supabase.table('exercises').select('*').range(offset, offset + 999).execute()
        if not response.data:
            break
        all_exercises.extend(response.data)
        offset += 1000
        if len(response.data) < 1000:
            break
    
    print(f"✅ Loaded {len(all_exercises)} exercises")
    print()
    
    # Filter to get exercises with good data
    valid_exercises = [
        ex for ex in all_exercises 
        if ex.get('name') and ex.get('primary_muscles')
    ]
    print(f"✅ {len(valid_exercises)} exercises with valid data")
    print()
    
    # Generate test cases - 100 random exercises
    test_exercises = random.sample(valid_exercises, min(100, len(valid_exercises)))
    
    # Different user equipment scenarios
    equipment_scenarios = [
        ["Bodyweight"],
        ["Dumbbells"],
        ["Barbell", "Dumbbells"],
        ["Dumbbells", "Cables", "Machines"],
        ["Barbell", "Dumbbells", "Cables", "Machines"],  # Full gym
    ]
    
    print(f"🧪 Running 100 test cases...")
    print()
    
    results = []
    for i, exercise in enumerate(test_exercises):
        # Rotate through equipment scenarios
        user_equipment = equipment_scenarios[i % len(equipment_scenarios)]
        
        result = run_test_case(i + 1, exercise, valid_exercises, user_equipment)
        results.append(result)
        
        if (i + 1) % 20 == 0:
            print(f"   Completed {i + 1}/100 tests...")
    
    print()
    
    # ========================================================================
    # RESULTS SUMMARY
    # ========================================================================
    
    print("=" * 90)
    print("📊 RESULTS SUMMARY")
    print("=" * 90)
    
    grades = Counter(r['grade'] for r in results)
    print("\n📈 Grade Distribution:")
    for grade in ['A', 'B', 'C', 'D', 'F']:
        count = grades.get(grade, 0)
        pct = (count / len(results)) * 100
        bar = '█' * int(pct / 5)
        print(f"   {grade}: {count:3d} ({pct:5.1f}%) {bar}")
    
    avg_score = sum(r['avg_score'] for r in results) / len(results)
    print(f"\n📊 Average Similarity Score: {avg_score:.1f}%")
    
    avg_alternatives = sum(r['alternatives_found'] for r in results) / len(results)
    print(f"📊 Average Alternatives Found: {avg_alternatives:.1f}")
    
    # Best examples
    print("\n" + "=" * 90)
    print("✅ BEST ALTERNATIVE MATCHES")
    print("=" * 90)
    
    best = sorted(results, key=lambda x: x['avg_score'], reverse=True)[:10]
    for r in best:
        print(f"\n🟢 Test #{r['test_id']}: {r['original_exercise']['name']}")
        print(f"   Movement: {r['original_exercise']['movement_pattern']} | Muscles: {r['original_exercise']['muscles']}")
        print(f"   Equipment: {r['original_exercise']['equipment']} | User has: {r['user_equipment']}")
        print(f"   Score: {r['avg_score']}% (Grade: {r['grade']})")
        print(f"   Top Alternatives:")
        for alt in r['alternatives'][:3]:
            print(f"      • {alt['name']} ({alt['equipment']}) - {alt['similarity_score']}pts")
            print(f"        Reasons: {', '.join(alt['reasons'][:2])}")
    
    # Worst examples
    print("\n" + "=" * 90)
    print("❌ WORST MATCHES (Need Improvement)")
    print("=" * 90)
    
    worst = sorted(results, key=lambda x: x['avg_score'])[:10]
    for r in worst:
        print(f"\n🔴 Test #{r['test_id']}: {r['original_exercise']['name']}")
        print(f"   Muscles: {r['original_exercise']['muscles']} | Equipment: {r['original_exercise']['equipment']}")
        print(f"   User has: {r['user_equipment']}")
        print(f"   Score: {r['avg_score']}% (Grade: {r['grade']})")
        print(f"   Alternatives Found: {r['alternatives_found']}")
        if r['issues']:
            print(f"   Issues: {', '.join(r['issues'][:3])}")
        if r['alternatives']:
            print(f"   Suggested:")
            for alt in r['alternatives'][:2]:
                print(f"      • {alt['name']} - {alt['muscles']}")
    
    # Analysis by movement pattern
    print("\n" + "=" * 90)
    print("📊 SCORES BY MOVEMENT PATTERN")
    print("=" * 90)
    
    pattern_scores = defaultdict(list)
    for r in results:
        pattern = r['original_exercise']['movement_pattern']
        pattern_scores[pattern].append(r['avg_score'])
    
    for pattern, scores in sorted(pattern_scores.items(), key=lambda x: sum(x[1])/len(x[1]) if x[1] else 0, reverse=True):
        avg = sum(scores) / len(scores) if scores else 0
        status = "✅" if avg >= 65 else "⚠️" if avg >= 50 else "❌"
        print(f"   {status} {pattern:20s}: {avg:5.1f}% (n={len(scores)})")
    
    # Analysis by equipment
    print("\n" + "=" * 90)
    print("📊 SCORES BY USER EQUIPMENT")
    print("=" * 90)
    
    equip_scores = defaultdict(list)
    for r in results:
        equip_key = ", ".join(sorted(r['user_equipment']))
        equip_scores[equip_key].append(r['avg_score'])
    
    for equip, scores in sorted(equip_scores.items(), key=lambda x: sum(x[1])/len(x[1]) if x[1] else 0, reverse=True):
        avg = sum(scores) / len(scores) if scores else 0
        status = "✅" if avg >= 65 else "⚠️" if avg >= 50 else "❌"
        print(f"   {status} {equip:45s}: {avg:5.1f}%")
    
    # Common issues
    print("\n" + "=" * 90)
    print("⚠️ MOST COMMON ISSUES")
    print("=" * 90)
    
    all_issues = []
    for r in results:
        all_issues.extend(r['issues'])
    
    issue_counts = Counter(all_issues)
    for issue, count in issue_counts.most_common(10):
        print(f"   {count:3d}x - {issue}")
    
    # Save results
    output_file = 'alternative_exercise_test_results.json'
    with open(output_file, 'w') as f:
        json.dump({
            'summary': {
                'total_tests': len(results),
                'grades': dict(grades),
                'avg_score': avg_score,
                'avg_alternatives_found': avg_alternatives
            },
            'results': results
        }, f, indent=2)
    
    print(f"\n📁 Results saved to: {output_file}")
    
    # Final grade
    final_grade = 'A' if avg_score >= 80 else 'B' if avg_score >= 65 else 'C' if avg_score >= 50 else 'D' if avg_score >= 35 else 'F'
    
    print("\n" + "=" * 90)
    print(f"📋 FINAL SYSTEM GRADE: {final_grade} ({avg_score:.1f}%)")
    print("=" * 90)
    
    # Recommendations
    print("\n💡 RECOMMENDATIONS:")
    if avg_score < 70:
        print("   1. Improve movement pattern matching in similarity algorithm")
        print("   2. Add more exercise metadata (movement type, body position)")
        print("   3. Consider secondary muscles in matching")
    if grades.get('F', 0) > 5:
        print("   4. Some exercises have very few valid alternatives - expand database")
    if avg_alternatives < 3:
        print("   5. Average alternatives is low - relax matching criteria")


if __name__ == "__main__":
    main()

