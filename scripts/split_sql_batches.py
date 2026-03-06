#!/usr/bin/env python3
"""
Split the large SQL file into smaller batches for Supabase
"""

import os
import re

INPUT_FILE = 'EXERCISE_FAMILY_UPDATES.sql'
OUTPUT_DIR = 'sql_batches'
BATCH_SIZE = 500  # Updates per batch

os.makedirs(OUTPUT_DIR, exist_ok=True)

print(f"Reading {INPUT_FILE}...")

with open(INPUT_FILE, 'r') as f:
    content = f.read()

# Extract the header (column additions, indexes)
header_match = re.search(r'^(.*?-- STEP 2: Update all exercises with classification data\n)', content, re.DOTALL)
header = header_match.group(1) if header_match else ""

# Extract the footer (verification queries, functions)
footer_match = re.search(r'(-- ============================================================================\n-- VERIFICATION QUERIES.*)', content, re.DOTALL)
footer = footer_match.group(1) if footer_match else ""

# Extract all UPDATE statements
updates = re.findall(r'UPDATE exercises SET \n.*?WHERE id = \'[^\']+\';', content, re.DOTALL)

print(f"Found {len(updates)} UPDATE statements")
print(f"Creating batches of {BATCH_SIZE} updates each...")

# Create batch 0 - just the schema changes
batch0_file = os.path.join(OUTPUT_DIR, 'batch_00_schema.sql')
with open(batch0_file, 'w') as f:
    f.write("""-- ============================================================================
-- BATCH 0: SCHEMA CHANGES (Run this FIRST!)
-- ============================================================================

-- Add new columns
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS exercise_family TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS base_exercise_name TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS complementary_families TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS is_equipment_primary BOOLEAN DEFAULT FALSE;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS equipment_category TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS duration_based BOOLEAN DEFAULT FALSE;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS recommended_sets INT DEFAULT 3;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS rest_seconds INT DEFAULT 60;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS muscles_worked_count INT DEFAULT 2;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_build_muscle INT DEFAULT 70;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_get_lean INT DEFAULT 70;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_home INT DEFAULT 50;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_gym INT DEFAULT 70;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_exercises_family ON exercises(exercise_family);
CREATE INDEX IF NOT EXISTS idx_exercises_equipment_category ON exercises(equipment_category);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_muscle ON exercises(priority_build_muscle DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_home ON exercises(priority_home DESC);

SELECT 'Schema changes complete! Now run batches 01 through the last one.' as status;
""")
print(f"Created {batch0_file}")

# Split updates into batches
batch_num = 1
for i in range(0, len(updates), BATCH_SIZE):
    batch_updates = updates[i:i + BATCH_SIZE]
    batch_file = os.path.join(OUTPUT_DIR, f'batch_{batch_num:02d}_updates.sql')
    
    with open(batch_file, 'w') as f:
        f.write(f"-- ============================================================================\n")
        f.write(f"-- BATCH {batch_num}: Updates {i+1} to {min(i+BATCH_SIZE, len(updates))} of {len(updates)}\n")
        f.write(f"-- ============================================================================\n\n")
        f.write('\n'.join(batch_updates))
        f.write(f"\n\nSELECT 'Batch {batch_num} complete! ({len(batch_updates)} exercises updated)' as status;\n")
    
    print(f"Created {batch_file} ({len(batch_updates)} updates)")
    batch_num += 1

# Create final batch with functions
final_batch = os.path.join(OUTPUT_DIR, f'batch_{batch_num:02d}_functions.sql')
with open(final_batch, 'w') as f:
    f.write("""-- ============================================================================
-- FINAL BATCH: Helper Functions (Run this LAST!)
-- ============================================================================

-- Function: Get equipment variants for an exercise (Swap 1-2)
CREATE OR REPLACE FUNCTION get_equipment_variants(
    p_exercise_id UUID,
    p_user_goal TEXT DEFAULT 'Build Muscle',
    p_location TEXT DEFAULT 'gym',
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    equipment TEXT,
    equipment_category TEXT,
    priority_score INT
) AS $$
DECLARE
    v_family TEXT;
    v_priority_column TEXT;
BEGIN
    SELECT exercise_family INTO v_family FROM exercises WHERE exercises.id = p_exercise_id;
    
    v_priority_column := CASE 
        WHEN p_location = 'home' THEN 'priority_home'
        WHEN p_user_goal = 'Get Lean' THEN 'priority_get_lean'
        WHEN p_user_goal = 'Build Muscle' THEN 'priority_build_muscle'
        ELSE 'priority_gym'
    END;
    
    RETURN QUERY EXECUTE format('
        SELECT e.id, e.name, e.equipment, e.equipment_category,
               e.%I as priority_score
        FROM exercises e
        WHERE e.exercise_family = $1
          AND e.id != $2
        ORDER BY e.%I DESC
        LIMIT $3
    ', v_priority_column, v_priority_column)
    USING v_family, p_exercise_id, p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get complementary exercises (Swap 3+)
CREATE OR REPLACE FUNCTION get_complementary_exercises(
    p_exercise_id UUID,
    p_user_goal TEXT DEFAULT 'Build Muscle',
    p_location TEXT DEFAULT 'gym',
    p_limit INT DEFAULT 15
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    equipment TEXT,
    exercise_family TEXT,
    priority_score INT
) AS $$
DECLARE
    v_complementary TEXT;
    v_priority_column TEXT;
BEGIN
    SELECT complementary_families INTO v_complementary FROM exercises WHERE exercises.id = p_exercise_id;
    
    v_priority_column := CASE 
        WHEN p_location = 'home' THEN 'priority_home'
        WHEN p_user_goal = 'Get Lean' THEN 'priority_get_lean'
        WHEN p_user_goal = 'Build Muscle' THEN 'priority_build_muscle'
        ELSE 'priority_gym'
    END;
    
    RETURN QUERY EXECUTE format('
        SELECT e.id, e.name, e.equipment, e.exercise_family,
               e.%I as priority_score
        FROM exercises e
        WHERE e.exercise_family = ANY(
            SELECT TRIM(unnest(string_to_array($1, '',')))
        )
          AND e.id != $2
        ORDER BY e.%I DESC
        LIMIT $3
    ', v_priority_column, v_priority_column)
    USING v_complementary, p_exercise_id, p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Smart swap (combines both based on swap count)
CREATE OR REPLACE FUNCTION get_smart_swap_suggestions(
    p_exercise_id UUID,
    p_swap_count INT DEFAULT 1,
    p_user_goal TEXT DEFAULT 'Build Muscle',
    p_location TEXT DEFAULT 'gym',
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    equipment TEXT,
    exercise_family TEXT,
    swap_type TEXT,
    priority_score INT
) AS $$
BEGIN
    IF p_swap_count < 3 THEN
        RETURN QUERY
        SELECT ev.id, ev.name, ev.equipment, 
               (SELECT e.exercise_family FROM exercises e WHERE e.id = ev.id),
               'equipment_variant'::TEXT as swap_type,
               ev.priority_score
        FROM get_equipment_variants(p_exercise_id, p_user_goal, p_location, p_limit) ev;
    ELSE
        RETURN QUERY
        SELECT ce.id, ce.name, ce.equipment, ce.exercise_family,
               'different_movement'::TEXT as swap_type,
               ce.priority_score
        FROM get_complementary_exercises(p_exercise_id, p_user_goal, p_location, p_limit) ce;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Verification
SELECT 
    'SUCCESS! All ' || COUNT(*) || ' exercises classified!' as status,
    COUNT(DISTINCT exercise_family) as unique_families
FROM exercises 
WHERE exercise_family IS NOT NULL;
""")
print(f"Created {final_batch}")

print(f"\n✅ Created {batch_num + 1} batch files in {OUTPUT_DIR}/")
print(f"\nRun them in order:")
print(f"  1. batch_00_schema.sql (adds columns)")
for i in range(1, batch_num):
    print(f"  {i+1}. batch_{i:02d}_updates.sql")
print(f"  {batch_num + 1}. batch_{batch_num:02d}_functions.sql (adds functions)")
