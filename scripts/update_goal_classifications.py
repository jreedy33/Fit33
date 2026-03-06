#!/usr/bin/env python3
"""
Update exercises with goal classification data.
Uses Supabase client to UPDATE fat_loss_rating, general_fitness_rating, is_compound, supersetable.
"""

import os
import load_env  # noqa: F401 — auto-loads .env credentials
import pandas as pd
from supabase import create_client

# Supabase credentials
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ehooeghabzefgoqzugrc.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_ANON_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0")

CSV_PATH = "/Users/josephreed/Desktop/Workout App/exercise_goal_classifications.csv"

def bool_convert(value):
    """Convert various bool representations to Python bool"""
    if pd.isna(value):
        return False
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() == 'true'
    return False

def int_or_default(value, default=5):
    """Convert to int or use default"""
    if pd.isna(value):
        return default
    try:
        return int(float(value))
    except:
        return default

def main():
    print("🚀 Goal Classification Update Script")
    print("=" * 60)
    
    # Initialize Supabase client
    print("📡 Connecting to Supabase...")
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    # Load CSV
    print(f"📂 Loading CSV from: {CSV_PATH}")
    df = pd.read_csv(CSV_PATH)
    print(f"✅ Loaded {len(df)} exercises")
    
    # Process and update
    success_count = 0
    error_count = 0
    not_found_count = 0
    errors = []
    
    total = len(df)
    
    print(f"\n📤 Updating exercises...")
    print("-" * 60)
    
    for idx, row in df.iterrows():
        exercise_id = row.get('id')
        
        if pd.isna(exercise_id) or exercise_id == '':
            continue
        
        # Prepare update data - only the 4 columns we need
        update_data = {
            'fat_loss_rating': int_or_default(row.get('fat_loss_rating'), 5),
            'general_fitness_rating': int_or_default(row.get('general_fitness_rating'), 5),
            'is_compound': bool_convert(row.get('is_compound')),
            'supersetable': bool_convert(row.get('supersetable'))
        }
        
        try:
            # UPDATE existing rows only (not upsert)
            result = supabase.table('exercises').update(update_data).eq('id', str(exercise_id)).execute()
            
            if result.data:
                success_count += 1
            else:
                not_found_count += 1
            
            # Progress indicator
            if (success_count + not_found_count + error_count) % 500 == 0:
                total_processed = success_count + not_found_count + error_count
                pct = (total_processed / total) * 100
                print(f"  ✅ {total_processed:,}/{total:,} processed ({pct:.1f}%) - {success_count:,} updated")
                
        except Exception as e:
            error_count += 1
            errors.append({
                'id': exercise_id,
                'name': row.get('name', 'Unknown'),
                'error': str(e)
            })
            
            # Show first few errors
            if error_count <= 3:
                print(f"  ❌ Error on {row.get('name', exercise_id)[:30]}: {str(e)[:50]}")
    
    # Final summary
    print("\n" + "=" * 60)
    print("📊 SUMMARY")
    print("=" * 60)
    print(f"  ✅ Successfully updated: {success_count:,}")
    print(f"  ⚠️  Not found (ID mismatch): {not_found_count:,}")
    print(f"  ❌ Errors: {error_count}")
    
    if errors:
        print(f"\n⚠️  First few errors:")
        for err in errors[:5]:
            print(f"    - {err['name']}: {err['error'][:60]}")
    
    # Verify
    print("\n🔍 Verifying update...")
    try:
        # Check some exercises that should be compound
        result = supabase.table('exercises').select('id, name, fat_loss_rating, is_compound, supersetable').eq('is_compound', True).limit(5).execute()
        print(f"  Compound exercises found: {len(result.data)}")
        for row in result.data[:3]:
            print(f"    ✅ {row['name'][:45]}: fat_loss={row['fat_loss_rating']}, compound={row['is_compound']}")
        
        # Count totals
        compound_result = supabase.table('exercises').select('id', count='exact').eq('is_compound', True).execute()
        non_superset = supabase.table('exercises').select('id', count='exact').eq('supersetable', False).execute()
        print(f"\n  📊 Final counts:")
        print(f"     Compound exercises: {compound_result.count}")
        print(f"     Non-supersetable: {non_superset.count}")
        
    except Exception as e:
        print(f"  Could not verify: {e}")
    
    print("\n✅ Done!")

if __name__ == "__main__":
    main()
