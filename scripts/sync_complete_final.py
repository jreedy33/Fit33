#!/usr/bin/env python3
"""Complete sync of ALL 36 columns from Final Master Correct.csv"""
import csv, json
from supabase import create_client

SUPABASE_URL = 'https://ehooeghabzefgoqzugrc.supabase.co'
SUPABASE_KEY = 'sb_secret_qF4j8_mWAjBSgto-7pmJlQ_J47n5qNO'

def parse_muscles(value):
    """Convert plain text or comma-separated to JSON array"""
    if not value or value == 'null' or value == '':
        return []
    if value.startswith('['):
        return json.loads(value)
    return [m.strip() for m in value.split(',') if m.strip()]

def clean_val(v):
    """Clean nulls and empty strings"""
    if not v or v == 'null' or v == '' or v == 'NULL':
        return None
    return v

def to_int(v):
    """Safe int conversion"""
    v = clean_val(v)
    if v and str(v).replace('-', '').isdigit():
        return int(v)
    return None

def to_bool(v):
    """Safe bool conversion"""
    return v in ['TRUE', 'True', 'true', '1', 1] if v else False

print('🚀 Syncing ALL columns from Final Master Correct.csv...\n')
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# Read CSV
with open('../Final Master Correct.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    exercises = [r for r in reader if r.get('id')]

print(f'📖 Loaded {len(exercises)} exercises from CSV')
print('💾 Syncing in batches of 50 (all 36 columns)...\n')

success = 0
errors = []

for i in range(0, len(exercises), 50):
    batch = []
    for row in exercises[i:i+50]:
        # Build complete data object with ALL columns
        data = {
            'id': row['id'],
            'name': row['name'],
            'workout_type': clean_val(row.get('workout_type')),
            'category': clean_val(row.get('category')) or 'General',
            'equipment': clean_val(row.get('equipment')),
            'primary_muscles': parse_muscles(row.get('primary_muscles')),
            'secondary_muscles': parse_muscles(row.get('secondary_muscles')),
            'description': clean_val(row.get('description')),
            'video_code': clean_val(row.get('video_code')),
            'video_filename': clean_val(row.get('video_filename')),
            'gender': clean_val(row.get('gender')),
            'is_custom': to_bool(row.get('is_custom')),
            'steps_to_perform': clean_val(row.get('steps_to_perform')),
            'movement_pattern': clean_val(row.get('movement_pattern')),
            'force_type': clean_val(row.get('force_type')),
            'movement_type': clean_val(row.get('movement_type')),
            'laterality': clean_val(row.get('laterality')),
            'plane_of_motion': clean_val(row.get('plane_of_motion')),
            'difficulty_level': to_int(row.get('difficulty_level')),
            'complexity_score': to_int(row.get('complexity_score')),
            'strength_rating': to_int(row.get('strength_rating')),
            'hypertrophy_rating': to_int(row.get('hypertrophy_rating')),
            'power_rating': to_int(row.get('power_rating')),
            'endurance_rating': to_int(row.get('endurance_rating')),
            'body_position': clean_val(row.get('body_position')),
            'bench_angle': clean_val(row.get('bench_angle')),
            'grip_type': clean_val(row.get('grip_type')),
            'grip_width': clean_val(row.get('grip_width')),
            'optimal_rep_range_min': to_int(row.get('optimal_rep_range_min')),
            'optimal_rep_range_max': to_int(row.get('optimal_rep_range_max')),
            'placement_in_workout': clean_val(row.get('placement_in_workout')),
            'fatigability': to_int(row.get('fatigability')),
            'popularity_score': to_int(row.get('popularity_score')),
            'home_gym_friendly': to_bool(row.get('home_gym_friendly')),
            'instructions': clean_val(row.get('instructions'))
        }
        batch.append(data)
    
    try:
        supabase.table('exercises').upsert(batch).execute()
        success += len(batch)
        print(f'   ✅ {success}/{len(exercises)} synced')
    except Exception as e:
        errors.append(f'Batch {i}-{i+50}: {str(e)[:100]}')
        print(f'   ❌ Error: {str(e)[:80]}')

print(f'\n🎉 Sync complete!')
print(f'✅ Success: {success}/{len(exercises)}')
if errors:
    print(f'❌ Errors: {len(errors)}')
    for err in errors[:5]:
        print(f'   - {err}')

