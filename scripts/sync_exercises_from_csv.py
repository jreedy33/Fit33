#!/usr/bin/env python3
"""
Sync exercises table with CSV - updates existing, deletes removed exercises
"""

import csv
import json
import os
import load_env  # noqa: F401 — auto-loads .env credentials
import sys
from supabase import create_client, Client

# Supabase connection
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_ANON_KEY')

def clean_value(value):
    """Clean CSV values"""
    if value == 'null' or value == '' or value == 'NULL':
        return None
    return value

def parse_json_array(value):
    """Parse JSON array strings"""
    if not value or value == 'null' or value == '[]':
        return []
    try:
        return json.loads(value)
    except:
        return []

def process_row(row):
    """Process CSV row"""
    data = {}
    
    # Text fields
    text_fields = [
        'id', 'name', 'category', 'equipment', 'description', 
        'video_code', 'video_filename', 'gender', 
        'steps_to_perform', 'movement_pattern', 'force_type',
        'movement_type', 'laterality', 'plane_of_motion',
        'difficulty_level', 'body_position', 'bench_angle',
        'grip_type', 'grip_width', 'placement_in_workout',
        'instructions', 'workout_type', 'created_at'
    ]
    
    for field in text_fields:
        if field in row:
            data[field] = clean_value(row[field])
    
    # JSON arrays
    if 'primary_muscles' in row:
        data['primary_muscles'] = parse_json_array(row['primary_muscles'])
    if 'secondary_muscles' in row:
        data['secondary_muscles'] = parse_json_array(row['secondary_muscles'])
    
    # Booleans
    if 'is_custom' in row:
        val = clean_value(row['is_custom'])
        data['is_custom'] = val in ['TRUE', 'True', 'true', '1'] if val else False
    
    if 'home_gym_friendly' in row:
        val = clean_value(row['home_gym_friendly'])
        data['home_gym_friendly'] = val in ['TRUE', 'True', 'true', '1'] if val else None
    
    # Numbers
    for field in ['complexity_score', 'strength_rating', 'hypertrophy_rating',
                  'power_rating', 'endurance_rating', 'optimal_rep_range_min',
                  'optimal_rep_range_max', 'fatigability', 'popularity_score']:
        if field in row:
            val = clean_value(row[field])
            if val:
                try:
                    data[field] = int(val) if '.' not in str(val) else float(val)
                except:
                    data[field] = None
    
    return data

def main():
    print("🚀 Syncing exercises from CSV to Supabase...\n")
    
    # Initialize Supabase
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    csv_path = '../Excercises Master (v1) - exercises_rows.csv'
    
    # Step 1: Read CSV and collect IDs
    print("📖 Reading CSV...")
    csv_exercise_ids = set()
    exercises_to_upsert = []
    
    with open(csv_path, 'r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            data = process_row(row)
            # Skip rows with no ID (empty rows)
            if not data.get('id'):
                continue
            csv_exercise_ids.add(data['id'])
            exercises_to_upsert.append(data)
    
    print(f"✅ Found {len(exercises_to_upsert)} exercises in CSV\n")
    
    # Step 2: Get all current exercise IDs from database
    print("📥 Fetching current exercises from database...")
    all_db_exercises = []
    offset = 0
    page_size = 1000
    
    while True:
        response = supabase.table('exercises').select('id').range(offset, offset + page_size - 1).execute()
        if not response.data:
            break
        all_db_exercises.extend(response.data)
        offset += page_size
        print(f"   Fetched {len(all_db_exercises)} exercises...")
        if len(response.data) < page_size:
            break
    
    db_exercise_ids = set(ex['id'] for ex in all_db_exercises)
    print(f"✅ Found {len(db_exercise_ids)} exercises in database\n")
    
    # Step 3: Find exercises to DELETE (in DB but not in CSV)
    to_delete = db_exercise_ids - csv_exercise_ids
    print(f"🗑️ Will DELETE {len(to_delete)} exercises removed from CSV")
    
    if to_delete:
        print("   Deleting exercises...")
        for exercise_id in to_delete:
            try:
                supabase.table('exercises').delete().eq('id', exercise_id).execute()
            except Exception as e:
                print(f"   ❌ Error deleting {exercise_id}: {e}")
        print(f"✅ Deleted {len(to_delete)} exercises\n")
    
    # Step 4: UPSERT exercises from CSV (update existing or insert new)
    print(f"💾 Upserting {len(exercises_to_upsert)} exercises...")
    
    # Batch upsert in chunks of 100
    chunk_size = 100
    upserted = 0
    errors = 0
    
    for i in range(0, len(exercises_to_upsert), chunk_size):
        chunk = exercises_to_upsert[i:i+chunk_size]
        try:
            supabase.table('exercises').upsert(chunk).execute()
            upserted += len(chunk)
            print(f"   ✅ {upserted}/{len(exercises_to_upsert)} exercises synced...")
        except Exception as e:
            errors += len(chunk)
            print(f"   ❌ Error with batch {i}-{i+len(chunk)}: {e}")
    
    print(f"\n🎉 Sync complete!")
    print(f"✅ Upserted: {upserted}")
    print(f"🗑️ Deleted: {len(to_delete)}")
    print(f"❌ Errors: {errors}")

if __name__ == '__main__':
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("❌ Missing credentials")
        sys.exit(1)
    main()

