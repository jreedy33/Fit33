#!/usr/bin/env python3
import os
import load_env  # noqa: F401 — auto-loads .env credentials
"""Quick script to check all user profiles in the database"""

from supabase import create_client, Client

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ehooeghabzefgoqzugrc.supabase.co")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)

print("\n" + "=" * 80)
print("ALL USER PROFILES")
print("=" * 80)

result = supabase.table("user_profiles").select("id, email, name, username, has_completed_onboarding").order("created_at", desc=True).limit(20).execute()

if result.data:
    for i, profile in enumerate(result.data):
        print(f"\n{i+1}. {profile.get('email', 'NO EMAIL')}")
        print(f"   ID: {profile.get('id')}")
        print(f"   Name: {profile.get('name', 'NULL')}")
        print(f"   Username: @{profile.get('username') or 'NULL ⚠️'}")
        print(f"   Onboarding: {profile.get('has_completed_onboarding')}")
else:
    print("No profiles found!")

# Also search specifically for variations
print("\n" + "=" * 80)
print("SEARCHING FOR 'joereed' OR 'jreedy'")
print("=" * 80)

search_terms = ['joereed', 'jreedy', 'icloud']
for term in search_terms:
    print(f"\nSearching for '{term}'...")
    try:
        result = supabase.table("user_profiles").select("id, email, name, username").ilike("email", f"%{term}%").execute()
        if result.data:
            for p in result.data:
                print(f"   Found: {p.get('email')} | @{p.get('username') or 'NULL'}")
        else:
            print(f"   No results")
    except Exception as e:
        print(f"   Error: {e}")
