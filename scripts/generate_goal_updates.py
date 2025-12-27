#!/usr/bin/env python3
"""
Generate SQL UPDATE statements from exercise_goal_classifications.csv
SLIM VERSION: Only imports 4 key columns:
- fat_loss_rating
- general_fitness_rating  
- is_compound
- supersetable
"""

import pandas as pd

# Configuration
CSV_PATH = "/Users/josephreed/Desktop/Workout App/exercise_goal_classifications.csv"
OUTPUT_SQL_PATH = "/Users/josephreed/Desktop/Workout App/UPDATE_GOAL_CLASSIFICATIONS.sql"

def bool_to_sql(value):
    """Convert Python bool to SQL boolean"""
    if pd.isna(value):
        return 'FALSE'
    if isinstance(value, bool):
        return 'TRUE' if value else 'FALSE'
    if isinstance(value, str):
        return 'TRUE' if value.lower() == 'true' else 'FALSE'
    return 'FALSE'

def int_or_default(value, default=5):
    """Convert to int or use default for SQL"""
    if pd.isna(value):
        return str(default)
    try:
        return str(int(float(value)))
    except:
        return str(default)

def main():
    print(f"📂 Loading CSV from: {CSV_PATH}")
    
    # Load CSV
    df = pd.read_csv(CSV_PATH)
    print(f"✅ Loaded {len(df)} exercises")
    
    sql_statements = []
    
    # Header
    sql_statements.append("-- ============================================================================")
    sql_statements.append("-- GOAL CLASSIFICATION DATA UPDATE (SLIM VERSION)")
    sql_statements.append(f"-- Total exercises: {len(df)}")
    sql_statements.append("-- Only 4 columns: fat_loss_rating, general_fitness_rating, is_compound, supersetable")
    sql_statements.append("-- ============================================================================")
    sql_statements.append("")
    sql_statements.append("-- Run GOAL_CLASSIFICATION_UPDATE.sql first to add new columns!")
    sql_statements.append("")
    sql_statements.append("BEGIN;")
    sql_statements.append("")
    
    batch_size = 500
    batch_count = 0
    
    for idx, row in df.iterrows():
        exercise_id = row['id']
        
        # Skip if no valid ID
        if pd.isna(exercise_id) or exercise_id == '':
            continue
        
        # Build UPDATE statement with only 4 columns
        sql = f"""UPDATE exercises SET fat_loss_rating = {int_or_default(row.get('fat_loss_rating'), 5)}, general_fitness_rating = {int_or_default(row.get('general_fitness_rating'), 5)}, is_compound = {bool_to_sql(row.get('is_compound'))}, supersetable = {bool_to_sql(row.get('supersetable'))} WHERE id = '{exercise_id}';"""
        
        sql_statements.append(sql)
        
        # Add batch markers for progress tracking
        if (idx + 1) % batch_size == 0:
            batch_count += 1
            sql_statements.append(f"-- ✓ Batch {batch_count}: {idx + 1} exercises processed")
            sql_statements.append("")
    
    sql_statements.append("")
    sql_statements.append("COMMIT;")
    sql_statements.append("")
    sql_statements.append(f"-- ✅ Total exercises updated: {len(df)}")
    sql_statements.append("")
    sql_statements.append("-- Verify with:")
    sql_statements.append("-- SELECT COUNT(*) as total,")
    sql_statements.append("--        COUNT(CASE WHEN fat_loss_rating != 5 THEN 1 END) as fat_loss_set,")
    sql_statements.append("--        COUNT(CASE WHEN is_compound = true THEN 1 END) as compound_count")
    sql_statements.append("-- FROM exercises;")
    
    # Write SQL file
    with open(OUTPUT_SQL_PATH, 'w') as f:
        f.write('\n'.join(sql_statements))
    
    print(f"✅ Generated SQL file: {OUTPUT_SQL_PATH}")
    print(f"📊 Total UPDATE statements: {len(df)}")
    
    # Show sample
    print("\n📝 Sample UPDATE statement:")
    for line in sql_statements:
        if line.startswith('UPDATE'):
            print(f"  {line}")
            break
    
    # Summary stats
    print("\n📊 Data Distribution:")
    print(f"  Fat Loss Rating distribution:")
    print(df['fat_loss_rating'].value_counts().sort_index().to_string())
    print(f"\n  Is Compound: {df['is_compound'].value_counts().to_dict()}")
    print(f"  Supersetable: {df['supersetable'].value_counts().to_dict()}")

if __name__ == "__main__":
    main()
