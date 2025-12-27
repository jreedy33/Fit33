#!/usr/bin/env python3
import csv, json, os
from supabase import create_client

SUPABASE_URL = 'https://ehooeghabzefgoqzugrc.supabase.co'
SUPABASE_KEY = 'sb_secret_qF4j8_mWAjBSgto-7pmJlQ_J47n5qNO'

def parse_muscles(value):
    """Convert 'Core' or 'Quads, Glutes' to ['Core'] or ['Quads', 'Glutes']"""
    if not value or value == 'null' or value == '':
        return []
    if value.startswith('['):
        return json.loads(value)
    # Split by comma and clean
    return [m.strip() for m in value.split(',') if m.strip()]

def clean_val(v):
    return None if (not v or v == 'null' or v == '') else v

print('🚀 Syncing Final Master Correct.csv...')
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

with open('../Final Master Correct.csv', 'r') as f:
    reader = csv.DictReader(f)
    exercises = [r for r in reader if r.get('id')]

print(f'📖 Found {len(exercises)} exercises')
print('💾 Updating in batches of 100...\n')

success = 0
for i in range(0, len(exercises), 100):
    batch = []
    for row in exercises[i:i+100]:
        data = {
            'id': row['id'],
            'name': row['name'],
            'workout_type': clean_val(row.get('workout_type')),
            'category': row['category'],
            'equipment': clean_val(row.get('equipment')),
            'primary_muscles': parse_muscles(row.get('primary_muscles')),
            'secondary_muscles': parse_muscles(row.get('secondary_muscles')),
            'description': clean_val(row.get('description')),
            'video_code': clean_val(row.get('video_code')),
            'video_filename': clean_val(row.get('video_filename')),
            'gender': clean_val(row.get('gender')),
            'is_custom': row.get('is_custom') in ['TRUE', 'True', '1'],
            'steps_to_perform': clean_val(row.get('steps_to_perform')),
            'movement_pattern': clean_val(row.get('movement_pattern')),
            'force_type': clean_val(row.get('force_type')),
            'movement_type': clean_val(row.get('movement_type')),
            'laterality': clean_val(row.get('laterality')),
            'plane_of_motion': clean_val(row.get('plane_of_motion')),
            'body_position': clean_val(row.get('body_position')),
            'bench_angle': clean_val(row.get('bench_angle')),
            'grip_type': clean_val(row.get('grip_type')),
            'grip_width': clean_val(row.get('grip_width')),
            'placement_in_workout': clean_val(row.get('placement_in_workout')),
            'home_gym_friendly': row.get('home_gym_friendly') in ['TRUE', 'True', '1'],
            'instructions': clean_val(row.get('instructions'))
        }
        
        # Numeric fields
        for field in ['difficulty_level', 'complexity_score', 'strength_rating', 
                      'hypertrophy_rating', 'power_rating', 'endurance_rating',
                      'optimal_rep_range_min', 'optimal_rep_range_max', 
                      'fatigability', 'popularity_score']:
            val = clean_val(row.get(field))
            data[field] = int(val) if val and val.isdigit() else None
        
        batch.append(data)
    
    supabase.table('exercises').upsert(batch).execute()
    success += len(batch)
    print(f'   ✅ {success}/{len(exercises)} synced')

print(f'\n🎉 Complete! Updated {success} exercises')

