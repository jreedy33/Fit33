#!/usr/bin/env python3
"""
Reads the new exercise CSV and generates SQL migration files for Supabase.

Strategy:
  1. Setup file: creates a persistent staging table
  2. Data files: batch INSERT INTO staging table (500 per file)
  3. Merge file: UPDATE existing, INSERT new, DELETE removed, cleanup
"""

import csv
import json
import os
import sys

CSV_PATH = os.path.expanduser("~/Downloads/New Excercise Data - Manus.csv")
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "supabase")
BATCH_SIZE = 500

COLUMNS = [
    "id", "name", "category", "equipment", "primary_muscles", "secondary_muscles",
    "description", "video_code", "video_filename", "gender", "is_custom",
    "created_at", "steps_to_perform", "movement_pattern", "force_type",
    "movement_type", "laterality", "plane_of_motion", "difficulty_level",
    "complexity_score", "strength_rating", "hypertrophy_rating", "power_rating",
    "endurance_rating", "body_position", "bench_angle", "grip_type", "grip_width",
    "optimal_rep_range_min", "optimal_rep_range_max", "placement_in_workout",
    "fatigability", "popularity_score", "home_gym_friendly", "instructions",
    "workout_type", "practicality_score", "fat_loss_rating", "general_fitness_rating",
    "is_compound", "supersetable", "exercise_family", "base_exercise_name",
    "complementary_families", "is_equipment_primary", "equipment_category",
    "duration_based", "recommended_sets", "rest_seconds", "muscles_worked_count",
    "priority_build_muscle", "priority_get_lean", "priority_home", "priority_gym",
]

TEXT_COLS = {
    "id", "name", "category", "equipment", "description", "video_code",
    "video_filename", "gender", "steps_to_perform", "movement_pattern",
    "force_type", "movement_type", "laterality", "plane_of_motion",
    "body_position", "bench_angle", "grip_type", "grip_width",
    "placement_in_workout", "instructions", "workout_type", "exercise_family",
    "base_exercise_name", "complementary_families", "equipment_category",
    "created_at",
}

BOOL_COLS = {
    "is_custom", "home_gym_friendly", "is_compound", "supersetable",
    "is_equipment_primary", "duration_based",
}

INT_COLS = {
    "difficulty_level", "complexity_score", "strength_rating", "hypertrophy_rating",
    "power_rating", "endurance_rating", "optimal_rep_range_min", "optimal_rep_range_max",
    "fatigability", "popularity_score", "practicality_score", "fat_loss_rating",
    "general_fitness_rating", "recommended_sets", "rest_seconds", "muscles_worked_count",
    "priority_build_muscle", "priority_get_lean", "priority_home", "priority_gym",
}

ARRAY_COLS = {"primary_muscles", "secondary_muscles"}


def escape_sql(val):
    if val is None:
        return "NULL"
    return val.replace("'", "''")


def convert_json_array_to_pg(val):
    """Convert JSON array string like '["Quads","Glutes"]' to PostgreSQL text[] literal."""
    if not val or val.strip() == "" or val.strip() == "[]":
        return "'{}'::text[]"
    try:
        items = json.loads(val)
        if not items:
            return "'{}'::text[]"
        escaped = [i.replace('"', '\\"').replace("'", "''") for i in items]
        inner = ",".join(f'"{e}"' for e in escaped)
        return f"'{{{inner}}}'::text[]"
    except (json.JSONDecodeError, TypeError):
        clean = val.replace("'", "''")
        return f"'{{{clean}}}'::text[]"


def format_value(col, val):
    raw = val.strip() if val else ""

    if raw == "" or raw.upper() == "NULL":
        if col in ARRAY_COLS:
            return "'{}'::text[]"
        return "NULL"

    if col in ARRAY_COLS:
        return convert_json_array_to_pg(raw)

    if col in BOOL_COLS:
        return "TRUE" if raw.upper() in ("TRUE", "T", "1", "YES") else "FALSE"

    if col in INT_COLS:
        try:
            return str(int(float(raw)))
        except (ValueError, TypeError):
            return "NULL"

    return f"'{escape_sql(raw)}'"


def read_csv():
    rows = []
    with open(CSV_PATH, "r", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header_row = None
        for i, row in enumerate(reader):
            if i == 0:
                if all(c.strip() == "" for c in row):
                    continue
                stripped = [c.strip() for c in row]
                if "id" in stripped and "name" in stripped:
                    header_row = stripped
                    continue
                else:
                    continue
            if i == 1 and header_row is None:
                stripped = [c.strip() for c in row]
                if "id" in stripped and "name" in stripped:
                    header_row = stripped
                    continue
            if header_row is None:
                continue
            if len(row) < len(header_row):
                row += [""] * (len(header_row) - len(row))
            record = {}
            for ci, col in enumerate(header_row):
                if col in COLUMNS:
                    record[col] = row[ci] if ci < len(row) else ""
            if record.get("id", "").strip():
                rows.append(record)
    return rows


def gen_setup_sql():
    path = os.path.join(OUTPUT_DIR, "exercise_replace_01_setup.sql")
    with open(path, "w") as f:
        f.write("-- Exercise Data Replace: Step 1 - Create staging table\n")
        f.write("-- Run this FIRST before the data files\n\n")
        f.write("DROP TABLE IF EXISTS _exercise_staging;\n\n")
        f.write("CREATE TABLE _exercise_staging (\n")
        col_defs = []
        for col in COLUMNS:
            if col in ARRAY_COLS:
                col_defs.append(f"    {col} TEXT[]")
            elif col in BOOL_COLS:
                col_defs.append(f"    {col} BOOLEAN")
            elif col in INT_COLS:
                col_defs.append(f"    {col} INTEGER")
            elif col == "id":
                col_defs.append(f"    {col} UUID PRIMARY KEY")
            elif col == "created_at":
                col_defs.append(f"    {col} TIMESTAMPTZ")
            else:
                col_defs.append(f"    {col} TEXT")
        f.write(",\n".join(col_defs))
        f.write("\n);\n")
    print(f"  Created: {os.path.basename(path)}")
    return path


def gen_data_sql(rows):
    paths = []
    total_batches = (len(rows) + BATCH_SIZE - 1) // BATCH_SIZE

    for batch_idx in range(total_batches):
        start = batch_idx * BATCH_SIZE
        end = min(start + BATCH_SIZE, len(rows))
        batch = rows[start:end]
        file_num = batch_idx + 2
        fname = f"exercise_replace_{file_num:02d}_data.sql"
        path = os.path.join(OUTPUT_DIR, fname)

        with open(path, "w") as f:
            f.write(f"-- Exercise Data Replace: Data batch {batch_idx + 1}/{total_batches}\n")
            f.write(f"-- Exercises {start + 1} to {end} of {len(rows)}\n\n")

            chunk_size = 100
            for chunk_start in range(0, len(batch), chunk_size):
                chunk_end = min(chunk_start + chunk_size, len(batch))
                chunk = batch[chunk_start:chunk_end]

                col_list = ", ".join(COLUMNS)
                f.write(f"INSERT INTO _exercise_staging ({col_list}) VALUES\n")

                value_rows = []
                for record in chunk:
                    vals = [format_value(col, record.get(col, "")) for col in COLUMNS]
                    value_rows.append(f"({', '.join(vals)})")

                f.write(",\n".join(value_rows))
                f.write(";\n\n")

        print(f"  Created: {fname} ({end - start} exercises)")
        paths.append(path)

    return paths


def gen_merge_sql(total_exercises):
    fname = "exercise_replace_99_merge.sql"
    path = os.path.join(OUTPUT_DIR, fname)

    update_cols = [c for c in COLUMNS if c not in ("id", "created_at")]

    with open(path, "w") as f:
        f.write("-- Exercise Data Replace: Final Step - Merge and cleanup\n")
        f.write("-- Run this AFTER all data files have been executed\n\n")
        f.write("BEGIN;\n\n")

        f.write(f"-- Verify staging table has expected row count\n")
        f.write(f"DO $$\n")
        f.write(f"DECLARE\n")
        f.write(f"    staging_count INTEGER;\n")
        f.write(f"BEGIN\n")
        f.write(f"    SELECT COUNT(*) INTO staging_count FROM _exercise_staging;\n")
        f.write(f"    RAISE NOTICE 'Staging table has % exercises', staging_count;\n")
        f.write(f"    IF staging_count < 100 THEN\n")
        f.write(f"        RAISE EXCEPTION 'Staging table has too few rows (%). Did you run all data files?', staging_count;\n")
        f.write(f"    END IF;\n")
        f.write(f"END $$;\n\n")

        f.write("-- Step 1: Update existing exercises with new data\n")
        f.write("UPDATE exercises e SET\n")
        set_clauses = [f"    {c} = s.{c}" for c in update_cols]
        f.write(",\n".join(set_clauses))
        f.write("\nFROM _exercise_staging s\n")
        f.write("WHERE e.id = s.id;\n\n")

        f.write("-- Step 2: Insert exercises that are new (exist in staging but not in exercises)\n")
        col_list = ", ".join(COLUMNS)
        f.write(f"INSERT INTO exercises ({col_list})\n")
        f.write(f"SELECT {col_list}\n")
        f.write(f"FROM _exercise_staging s\n")
        f.write(f"WHERE NOT EXISTS (SELECT 1 FROM exercises e WHERE e.id = s.id);\n\n")

        f.write("-- Step 3: Delete exercises that were removed (exist in DB but not in new data)\n")
        f.write("-- Only deletes non-custom exercises to preserve user-created ones\n")
        f.write("DELETE FROM exercises\n")
        f.write("WHERE is_custom = FALSE\n")
        f.write("  AND id NOT IN (SELECT id FROM _exercise_staging);\n\n")

        f.write("-- Report results\n")
        f.write("DO $$\n")
        f.write("DECLARE\n")
        f.write("    final_count INTEGER;\n")
        f.write("    custom_count INTEGER;\n")
        f.write("BEGIN\n")
        f.write("    SELECT COUNT(*) INTO final_count FROM exercises WHERE is_custom = FALSE;\n")
        f.write("    SELECT COUNT(*) INTO custom_count FROM exercises WHERE is_custom = TRUE;\n")
        f.write("    RAISE NOTICE '✅ Exercise replace complete!';\n")
        f.write("    RAISE NOTICE '   Standard exercises: %', final_count;\n")
        f.write("    RAISE NOTICE '   Custom (user) exercises preserved: %', custom_count;\n")
        f.write("END $$;\n\n")

        f.write("COMMIT;\n\n")

        f.write("-- Step 4: Refresh materialized view if it exists\n")
        f.write("DO $$\n")
        f.write("BEGIN\n")
        f.write("    IF EXISTS (\n")
        f.write("        SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_public_exercises'\n")
        f.write("    ) THEN\n")
        f.write("        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_public_exercises;\n")
        f.write("        RAISE NOTICE '✅ Materialized view mv_public_exercises refreshed';\n")
        f.write("    ELSE\n")
        f.write("        RAISE NOTICE 'ℹ️ No materialized view to refresh';\n")
        f.write("    END IF;\n")
        f.write("END $$;\n\n")

        f.write("-- Step 5: Drop staging table\n")
        f.write("DROP TABLE IF EXISTS _exercise_staging;\n")
        f.write("RAISE NOTICE '🧹 Staging table dropped';\n")

    print(f"  Created: {fname}")
    return path


def main():
    print(f"Reading CSV: {CSV_PATH}")
    rows = read_csv()
    print(f"  Found {len(rows)} exercises\n")

    if not rows:
        print("ERROR: No exercises found in CSV!")
        sys.exit(1)

    print("Generating SQL files...")
    gen_setup_sql()
    gen_data_sql(rows)
    gen_merge_sql(len(rows))

    print(f"\nDone! Run the SQL files in the Supabase SQL Editor in order:")
    print(f"  1. exercise_replace_01_setup.sql")
    print(f"  2. exercise_replace_02_data.sql through the last data file")
    print(f"  3. exercise_replace_99_merge.sql")


if __name__ == "__main__":
    main()
