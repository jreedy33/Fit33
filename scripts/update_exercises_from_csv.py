#!/usr/bin/env python3
"""
Update exercises table in Supabase from improved CSV
"""

import csv
import json
import os
from supabase import create_client, Client

# Supabase connection (you'll need to set these environment variables)
SUPABASE_URL = os.getenv('SUPABASE_URL', 'YOUR_SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_ANON_KEY', 'YOUR_SUPABASE_KEY')

def clean_value(value):
    """Clean CSV values - convert 'null' string to None, handle empty strings"""
    if value == 'null' or value == '' or value == 'NULL':
        return None
    return value

def parse_json_array(value):
    """Parse JSON array strings like '["Abs"]' into actual arrays"""
    if not value or value == 'null' or value == '[]':
        return []
    try:
        return json.loads(value)
    except:
        # If it's already a list or parsing fails, return as is or empty
        if isinstance(value, list):
            return value
        return []

def process_row(row):
    """Process a CSV row into a format suitable for Supabase"""
    # Start with the ID (required for updates)
    data = {
        'id': row['id']
    }
    
    # Simple text fields
    simple_fields = [
        'name', 'category', 'equipment', 'description', 
        'video_code', 'video_filename', 'gender', 
        'steps_to_perform', 'movement_pattern', 'force_type',
        'movement_type', 'laterality', 'plane_of_motion',
        'difficulty_level', 'body_position', 'bench_angle',
        'grip_type', 'grip_width', 'placement_in_workout',
        'instructions', 'workout_type'
    ]
    
    for field in simple_fields:
        if field in row:
            data[field] = clean_value(row[field])
    
    # JSON array fields
    if 'primary_muscles' in row:
        data['primary_muscles'] = parse_json_array(row['primary_muscles'])
    if 'secondary_muscles' in row:
        data['secondary_muscles'] = parse_json_array(row['secondary_muscles'])
    
    # Boolean fields
    if 'is_custom' in row:
        val = clean_value(row['is_custom'])
        data['is_custom'] = val in ['TRUE', 'True', 'true', '1', 1] if val else False
    
    if 'home_gym_friendly' in row:
        val = clean_value(row['home_gym_friendly'])
        data['home_gym_friendly'] = val in ['TRUE', 'True', 'true', '1', 1] if val else None
    
    # Numeric fields
    numeric_fields = [
        'complexity_score', 'strength_rating', 'hypertrophy_rating',
        'power_rating', 'endurance_rating', 'optimal_rep_range_min',
        'optimal_rep_range_max', 'fatigability', 'popularity_score'
    ]
    
    for field in numeric_fields:
        if field in row:
            val = clean_value(row[field])
            if val:
                try:
                    # Try to convert to integer or float
                    if '.' in str(val):
                        data[field] = float(val)
                    else:
                        data[field] = int(val)
                except:
                    data[field] = None
            else:
                data[field] = None
    
    # Don't update created_at - let it keep the original value
    
    return data

def main():
    print("🚀 Starting exercise update from CSV...\n")
    
    # Initialize Supabase client
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    # Read CSV
    csv_path = '../Excercises Master (v1) - exercises_rows.csv'
    
    updated_count = 0
    error_count = 0
    
    with open(csv_path, 'r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        
        for i, row in enumerate(reader, 1):
            try:
                # Process the row
                data = process_row(row)
                exercise_id = data.pop('id')  # Remove ID from data (used in WHERE clause)
                
                # Update in Supabase
                result = supabase.table('exercises').update(data).eq('id', exercise_id).execute()
                
                updated_count += 1
                
                if i % 100 == 0:
                    print(f"✅ Processed {i} exercises...")
                    
            except Exception as e:
                error_count += 1
                print(f"❌ Error updating {row.get('name', 'unknown')} (ID: {row.get('id', 'unknown')}): {e}")
                
                if error_count > 10:
                    print("\n⚠️ Too many errors, stopping...")
                    break
    
    print(f"\n🎉 Update complete!")
    print(f"✅ Successfully updated: {updated_count}")
    print(f"❌ Errors: {error_count}")

if __name__ == '__main__':
    # Check if Supabase credentials are set
    if SUPABASE_URL == 'YOUR_SUPABASE_URL' or SUPABASE_KEY == 'YOUR_SUPABASE_KEY':
        print("⚠️ Please set SUPABASE_URL and SUPABASE_ANON_KEY environment variables")
        print("\nExample:")
        print("export SUPABASE_URL='https://your-project.supabase.co'")
        print("export SUPABASE_ANON_KEY='your-anon-key'")
        print("\nThen run: python3 update_exercises_from_csv.py")
    else:
        main()

