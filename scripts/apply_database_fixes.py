#!/usr/bin/env python3
"""
Apply Database Fixes
====================
Reads the audit CSV and applies the suggested fixes to Supabase.
"""

import csv
from supabase import create_client
from typing import Dict, List
import json

# Supabase connection
SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

# CSV file path
CSV_FILE = "/Users/josephreed/Desktop/Workout App/exercise_audit_20251227_191840.csv"

def parse_list_field(value: str) -> List[str]:
    """Parse a string representation of a list back to a list"""
    if not value or value == "[]":
        return []
    
    # Handle Python list string format: ['item1', 'item2']
    try:
        # Try to eval it (safe for simple lists)
        if value.startswith("[") and value.endswith("]"):
            # Replace single quotes with double quotes for JSON parsing
            json_str = value.replace("'", '"')
            return json.loads(json_str)
    except:
        pass
    
    # Fallback: split by comma
    return [v.strip().strip("'\"[]") for v in value.split(",") if v.strip()]

def read_fixes_from_csv() -> List[Dict]:
    """Read the audit CSV and extract fixes to apply"""
    fixes = []
    
    with open(CSV_FILE, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        current_original = None
        
        for row in reader:
            row_type = row.get('_ROW_TYPE', '')
            
            if row_type == 'ORIGINAL':
                current_original = row
            elif row_type == 'SUGGESTED_FIX' and current_original:
                # Compare original and fix to find what changed
                exercise_id = row.get('id')
                exercise_name = row.get('name')
                issues = current_original.get('_ISSUES', '')
                
                changes = {}
                
                # Check what fields changed
                if row.get('category') != current_original.get('category'):
                    changes['category'] = row.get('category')
                
                if row.get('primary_muscles') != current_original.get('primary_muscles'):
                    changes['primary_muscles'] = parse_list_field(row.get('primary_muscles', '[]'))
                
                if row.get('secondary_muscles') != current_original.get('secondary_muscles'):
                    changes['secondary_muscles'] = parse_list_field(row.get('secondary_muscles', '[]'))
                
                if row.get('equipment') != current_original.get('equipment'):
                    changes['equipment'] = row.get('equipment')
                
                if changes:
                    fixes.append({
                        'id': exercise_id,
                        'name': exercise_name,
                        'issues': issues,
                        'changes': changes,
                        'original': {
                            'category': current_original.get('category'),
                            'primary_muscles': current_original.get('primary_muscles'),
                        }
                    })
                
                current_original = None
    
    return fixes

def apply_fixes(fixes: List[Dict], dry_run: bool = False):
    """Apply fixes to Supabase"""
    
    if not fixes:
        print("No fixes to apply!")
        return
    
    print(f"\n{'='*70}")
    print(f"🔧 APPLYING {len(fixes)} FIXES TO DATABASE")
    print(f"{'='*70}")
    
    if dry_run:
        print("⚠️  DRY RUN MODE - No changes will be made\n")
    
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    success_count = 0
    error_count = 0
    
    for i, fix in enumerate(fixes, 1):
        exercise_id = fix['id']
        exercise_name = fix['name']
        changes = fix['changes']
        issues = fix['issues']
        original = fix['original']
        
        print(f"\n{i}. {exercise_name}")
        print(f"   ID: {exercise_id}")
        print(f"   Issues: {issues}")
        print(f"   Changes:")
        for field, new_value in changes.items():
            old_value = original.get(field, 'N/A')
            print(f"      {field}: {old_value} → {new_value}")
        
        if not dry_run:
            try:
                response = supabase.table("exercises").update(changes).eq("id", exercise_id).execute()
                
                if response.data:
                    print(f"   ✅ Updated successfully")
                    success_count += 1
                else:
                    print(f"   ❌ No data returned - may not have updated")
                    error_count += 1
                    
            except Exception as e:
                print(f"   ❌ Error: {e}")
                error_count += 1
        else:
            print(f"   ⏸️  Would update (dry run)")
            success_count += 1
    
    print(f"\n{'='*70}")
    print(f"📊 SUMMARY")
    print(f"{'='*70}")
    print(f"   Total fixes: {len(fixes)}")
    print(f"   Successful: {success_count}")
    print(f"   Errors: {error_count}")
    
    if dry_run:
        print(f"\n⚠️  This was a DRY RUN. Run with dry_run=False to apply changes.")

def main():
    print("\n" + "="*70)
    print("🔍 READING FIXES FROM AUDIT CSV")
    print("="*70)
    
    fixes = read_fixes_from_csv()
    
    print(f"\n📋 Found {len(fixes)} exercises to fix:")
    
    for i, fix in enumerate(fixes, 1):
        print(f"   {i}. {fix['name']}")
        print(f"      Issue: {fix['issues']}")
        print(f"      Fix: {fix['changes']}")
    
    # First do a dry run
    print("\n" + "="*70)
    print("🔍 DRY RUN - Previewing changes")
    print("="*70)
    apply_fixes(fixes, dry_run=True)
    
    # Ask for confirmation (in script mode, we'll just proceed)
    print("\n" + "="*70)
    print("🚀 APPLYING CHANGES TO DATABASE")
    print("="*70)
    apply_fixes(fixes, dry_run=False)
    
    print("\n✅ Database fixes complete!")

if __name__ == "__main__":
    main()
