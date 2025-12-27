#!/usr/bin/env python3
import csv
import json
import os
from supabase import create_client

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_ANON_KEY')

def clean_value(value):
    if value == 'null' or value == '' or value == 'NULL':
        return None
    return value

def parse_json_array(value):
    if not value or value == 'null' or value == '[]':
        return []
    try:
        return json.loads(value)
    except:
        return []

def process_row(row):
    data = {}
    for field in ['id', 'name', 'category', 'equipment', 'description', 'video_code', 
                  'video_filename', 'gender', 'steps_to_perform', 'movement_pattern', 
                  'force_type', 'movement_type', 'laterality', 'plane_of_motion',
                  'body_position', 'bench_angle', 'grip_type', 'grip_width', 
                  'placement_in_workout', 'instructions', 'workout_type', 'created_at']:
        if field in row:
            data[field] = clean_value(row[field])
    
    if 'primary_muscles' in row:
        data['primary_muscles'] = parse_json_array(row['primary_muscles'])
    if 'secondary_muscles' in row:
        data['secondary_muscles'] = parse_json_array(row['secondary_muscles'])
    
    for field in ['is_custom', 'home_gym_friendly']:
        if field in row:
            val = clean_value(row[field])
            data[field] = val in ['TRUE', 'True', 'true', '1'] if val else (False if field == 'is_custom' else None)
    
    for field in ['complexity_score', 'strength_rating', 'hypertrophy_rating',
                  'power_rating', 'endurance_rating', 'optimal_rep_range_min',
                  'optimal_rep_range_max', 'fatigability', 'popularity_score', 'difficulty_level']:
        if field in row:
            val = clean_value(row[field])
            if val:
                try:
                    data[field] = int(val)
                except:
                    data[field] = None
    
    return data

# Run one-by-one to see errors
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
csv_path = '../Excercises Master (v1) - exercises_rows.csv'

failed_exercises = []
success = 0

with open(csv_path, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 1):
        data = process_row(row)
        if not data.get('id'):
            continue
        
        try:
            supabase.table('exercises').upsert(data).execute()
            success += 1
            if success % 500 == 0:
                print(f"✅ {success} synced...")
        except Exception as e:
            failed_exercises.append({
                'id': data.get('id'),
                'name': data.get('name'),
                'error': str(e)
            })

print(f"\n✅ Success: {success}")
print(f"❌ Failed: {len(failed_exercises)}")

if failed_exercises:
    print("\n❌ Failed exercises:")
    for ex in failed_exercises[:20]:  # Show first 20
        print(f"   - {ex['name']} (ID: {ex['id'][:8]}...): {ex['error'][:80]}")

