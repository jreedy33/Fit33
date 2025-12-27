#!/usr/bin/env python3
"""
Fix Exercise Classification Issues
==================================
Fixes identified issues from the test suite:
1. Misclassified exercises (leg curl in bicep_curl family)
2. Missing complementary families (antagonist pairings)
3. Missing isolation pairings
"""

import os
import json
from datetime import datetime
from supabase import create_client

# Supabase credentials
SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)


def fetch_all_exercises():
    """Fetch all exercises"""
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
    
    return all_exercises


def find_misclassified_exercises(exercises):
    """Find exercises that are misclassified"""
    issues = []
    
    # Pattern: exercises with "leg curl" in name but classified as bicep_curl
    for ex in exercises:
        name = (ex.get('name') or '').lower()
        family = ex.get('exercise_family', '')
        
        # Leg curl misclassified as bicep_curl
        if 'leg curl' in name and family == 'bicep_curl':
            issues.append({
                'id': ex.get('id'),
                'name': ex.get('name'),
                'current_family': family,
                'correct_family': 'leg_curl',
                'issue': 'leg_curl misclassified as bicep_curl'
            })
        
        # Hamstring curl misclassified as bicep_curl
        if 'hamstring curl' in name and family == 'bicep_curl':
            issues.append({
                'id': ex.get('id'),
                'name': ex.get('name'),
                'current_family': family,
                'correct_family': 'leg_curl',
                'issue': 'hamstring_curl misclassified as bicep_curl'
            })
        
        # Wrist curl should stay in bicep_curl (it's arm work)
        # But Nordic curl, lying leg curl, etc. should be leg_curl
        
        # Check for other curl misclassifications
        if family == 'bicep_curl':
            # These should NOT be in bicep_curl
            wrong_patterns = [
                ('leg curl', 'leg_curl'),
                ('hamstring curl', 'leg_curl'),
                ('nordic curl', 'leg_curl'),
                ('lying curl', 'leg_curl'),  # Could be leg curl if context suggests
            ]
            
            for pattern, correct in wrong_patterns:
                if pattern in name and 'bicep' not in name and 'arm' not in name:
                    if ex not in [i for i in issues]:  # Avoid duplicates
                        issues.append({
                            'id': ex.get('id'),
                            'name': ex.get('name'),
                            'current_family': family,
                            'correct_family': correct,
                            'issue': f'{pattern} misclassified as bicep_curl'
                        })
    
    return issues


def find_complementary_issues(exercises):
    """Find exercises with missing complementary families"""
    updates_needed = []
    
    # Build a lookup by family
    by_family = {}
    for ex in exercises:
        family = ex.get('exercise_family', '')
        if family:
            if family not in by_family:
                by_family[family] = []
            by_family[family].append(ex)
    
    # Define the correct complementary relationships
    CORRECT_COMPLEMENTARY = {
        # Tricep exercises should pair with bicep exercises (antagonist)
        'tricep_pushdown': 'bicep_curl, tricep_extension, skull_crusher, dip',
        'tricep_extension': 'bicep_curl, tricep_pushdown, skull_crusher, dip',
        'skull_crusher': 'bicep_curl, tricep_pushdown, tricep_extension, dip',
        
        # Bicep exercises should pair with tricep exercises (antagonist)
        'bicep_curl': 'tricep_pushdown, tricep_extension, hammer_curl, preacher_curl',
        'hammer_curl': 'tricep_pushdown, tricep_extension, bicep_curl, preacher_curl',
        'preacher_curl': 'tricep_pushdown, tricep_extension, bicep_curl, hammer_curl',
        'concentration_curl': 'tricep_pushdown, tricep_extension, bicep_curl, hammer_curl',
        
        # Deadlift should include leg_curl and back_extension
        'deadlift': 'romanian_deadlift, leg_curl, back_extension, hip_thrust, good_morning',
        'romanian_deadlift': 'deadlift, leg_curl, hip_thrust, good_morning, back_extension',
        
        # Bench press and chest exercises
        'bench_press': 'incline_bench_press, chest_fly, tricep_pushdown, dip, decline_bench_press',
        'incline_bench_press': 'bench_press, chest_fly, shoulder_press, decline_bench_press',
        'decline_bench_press': 'bench_press, incline_bench_press, chest_fly, dip',
        
        # Back exercises - antagonist to chest
        'bent_over_row': 'lat_pulldown, pull_up, bicep_curl, face_pull, seated_row',
        'lat_pulldown': 'bent_over_row, pull_up, bicep_curl, face_pull, seated_row',
        'pull_up': 'lat_pulldown, bent_over_row, bicep_curl, chin_up',
        'chin_up': 'lat_pulldown, bent_over_row, bicep_curl, pull_up',
        'seated_row': 'lat_pulldown, bent_over_row, face_pull, pull_up',
        
        # Squat and leg exercises
        'squat': 'leg_press, leg_extension, leg_curl, lunge, front_squat, hack_squat',
        'front_squat': 'squat, leg_press, leg_extension, goblet_squat',
        'leg_press': 'squat, leg_extension, leg_curl, hack_squat, lunge',
        'leg_extension': 'leg_curl, squat, leg_press, lunge',
        'leg_curl': 'leg_extension, romanian_deadlift, hip_thrust, glute_bridge',
        
        # Shoulder exercises
        'shoulder_press': 'lateral_raise, front_raise, rear_delt_fly, upright_row',
        'lateral_raise': 'shoulder_press, front_raise, rear_delt_fly, upright_row',
        'front_raise': 'shoulder_press, lateral_raise, rear_delt_fly',
        'rear_delt_fly': 'shoulder_press, lateral_raise, face_pull, bent_over_row',
        
        # Hip/glute exercises
        'hip_thrust': 'glute_bridge, romanian_deadlift, leg_curl, squat',
        'glute_bridge': 'hip_thrust, romanian_deadlift, leg_curl',
        
        # Core exercises
        'crunch': 'plank, leg_raise, russian_twist, sit_up',
        'plank': 'crunch, leg_raise, russian_twist, dead_bug',
        'leg_raise': 'crunch, plank, russian_twist, hanging_knee_raise',
        'russian_twist': 'crunch, plank, leg_raise, wood_chop',
    }
    
    # Check each family and update if needed
    for family, exercises_in_family in by_family.items():
        if family in CORRECT_COMPLEMENTARY:
            correct_comp = CORRECT_COMPLEMENTARY[family]
            
            # Check first exercise in family
            sample = exercises_in_family[0]
            current_comp = sample.get('complementary_families', '')
            
            # If different, all exercises in this family need updating
            if current_comp != correct_comp:
                for ex in exercises_in_family:
                    updates_needed.append({
                        'id': ex.get('id'),
                        'name': ex.get('name'),
                        'family': family,
                        'current_complementary': ex.get('complementary_families', ''),
                        'correct_complementary': correct_comp
                    })
    
    return updates_needed


def apply_fixes(misclassified, complementary_updates):
    """Apply all fixes to the database"""
    
    print("\n" + "=" * 80)
    print("🔧 APPLYING FIXES")
    print("=" * 80)
    
    fixed_count = 0
    errors = []
    
    # Fix misclassified exercises
    print(f"\n📝 Fixing {len(misclassified)} misclassified exercises...")
    for issue in misclassified:
        try:
            # Determine base_exercise_name
            name = issue['name']
            correct_family = issue['correct_family']
            
            # Create base name by removing equipment
            base_name = name
            for eq in ['(Barbell)', '(Dumbbell)', '(Cable)', '(Machine)', '(Band)', '(Kettlebell)', '(Bodyweight)']:
                base_name = base_name.replace(eq, '').strip()
            
            # Get correct complementary families
            comp_families = {
                'leg_curl': 'leg_extension, romanian_deadlift, hip_thrust, glute_bridge',
            }.get(correct_family, '')
            
            response = supabase.table('exercises').update({
                'exercise_family': correct_family,
                'base_exercise_name': base_name,
                'complementary_families': comp_families
            }).eq('id', issue['id']).execute()
            
            fixed_count += 1
            print(f"   ✅ Fixed: {issue['name']} -> {correct_family}")
            
        except Exception as e:
            errors.append({'issue': issue, 'error': str(e)})
            print(f"   ❌ Error fixing {issue['name']}: {e}")
    
    # Fix complementary families
    print(f"\n📝 Fixing {len(complementary_updates)} complementary family entries...")
    
    # Group by family for efficiency
    by_family = {}
    for update in complementary_updates:
        family = update['family']
        if family not in by_family:
            by_family[family] = {
                'correct_complementary': update['correct_complementary'],
                'exercises': []
            }
        by_family[family]['exercises'].append(update)
    
    for family, data in by_family.items():
        try:
            # Update all exercises in this family at once
            response = supabase.table('exercises').update({
                'complementary_families': data['correct_complementary']
            }).eq('exercise_family', family).execute()
            
            fixed_count += len(data['exercises'])
            print(f"   ✅ Updated {len(data['exercises'])} exercises in '{family}' family")
            print(f"      New complementary: {data['correct_complementary'][:60]}...")
            
        except Exception as e:
            errors.append({'family': family, 'error': str(e)})
            print(f"   ❌ Error updating {family}: {e}")
    
    return fixed_count, errors


def main():
    print("=" * 80)
    print("🔧 EXERCISE CLASSIFICATION FIX SCRIPT")
    print("=" * 80)
    print()
    
    # Fetch exercises
    exercises = fetch_all_exercises()
    print(f"✅ Loaded {len(exercises)} exercises")
    
    # Find issues
    print("\n" + "=" * 80)
    print("🔍 FINDING ISSUES")
    print("=" * 80)
    
    # 1. Find misclassified exercises
    misclassified = find_misclassified_exercises(exercises)
    print(f"\n📋 Found {len(misclassified)} misclassified exercises:")
    for issue in misclassified[:20]:  # Show first 20
        print(f"   • {issue['name']}")
        print(f"     Current: {issue['current_family']} -> Correct: {issue['correct_family']}")
    if len(misclassified) > 20:
        print(f"   ... and {len(misclassified) - 20} more")
    
    # 2. Find complementary family issues
    complementary_updates = find_complementary_issues(exercises)
    
    # Count unique families needing updates
    families_to_update = set(u['family'] for u in complementary_updates)
    print(f"\n📋 Found {len(families_to_update)} families needing complementary updates:")
    for family in sorted(families_to_update):
        count = sum(1 for u in complementary_updates if u['family'] == family)
        print(f"   • {family}: {count} exercises")
    
    # Apply fixes
    if misclassified or complementary_updates:
        print("\n" + "=" * 80)
        print("⚠️  READY TO APPLY FIXES")
        print("=" * 80)
        print(f"   • {len(misclassified)} misclassified exercises to fix")
        print(f"   • {len(complementary_updates)} complementary family entries to update")
        
        # Apply the fixes
        fixed_count, errors = apply_fixes(misclassified, complementary_updates)
        
        print("\n" + "=" * 80)
        print("📊 RESULTS")
        print("=" * 80)
        print(f"   ✅ Fixed: {fixed_count} entries")
        print(f"   ❌ Errors: {len(errors)}")
        
        if errors:
            print("\n⚠️ Errors encountered:")
            for err in errors[:10]:
                print(f"   • {err}")
    else:
        print("\n✅ No issues found - database is clean!")
    
    print("\n" + "=" * 80)
    print("✅ FIX SCRIPT COMPLETE")
    print("=" * 80)


if __name__ == "__main__":
    main()
