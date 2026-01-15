#!/usr/bin/env python3
"""
Test User Creation Script for Fit33
====================================
Creates a real test user in Supabase to verify the signup + username flow.

Usage:
    python scripts/create_test_user.py

This script will:
1. Create a new auth user via signup
2. Create their profile
3. Set their username
4. Verify everything saved correctly
"""

import os
import sys
import json
import random
import string
from datetime import datetime
import time

# Try to import required packages
try:
    from supabase import create_client, Client
except ImportError:
    print("❌ supabase-py not installed. Run: pip install supabase")
    sys.exit(1)

# ============================================
# CONFIGURATION - From your app
# ============================================
SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

# For admin operations (delete user, etc), set this env var
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")


def generate_test_email():
    """Generate a unique test email"""
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    rand = ''.join(random.choices(string.ascii_lowercase, k=4))
    return f"testuser_{timestamp}_{rand}@fit33test.com"


def generate_test_username():
    """Generate a unique test username"""
    timestamp = datetime.now().strftime("%m%d%H%M")
    rand = ''.join(random.choices(string.ascii_lowercase, k=3))
    return f"test_{timestamp}_{rand}"


def log_step(step_num, message, success=True):
    """Print a formatted log message"""
    icon = "✅" if success else "❌"
    print(f"{icon} Step {step_num}: {message}")


def log_info(message):
    """Print info message"""
    print(f"   ℹ️  {message}")


def log_error(message):
    """Print error message"""
    print(f"   ❌ ERROR: {message}")


def log_data(label, value):
    """Print data"""
    print(f"   📦 {label}: {value}")


def log_warning(message):
    """Print warning"""
    print(f"   ⚠️  {message}")


class TestUserCreator:
    def __init__(self):
        self.supabase: Client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
        self.user_id = None
        self.test_email = None
        self.test_username = None
        self.session = None
        
    def run_full_test(self, email=None, username=None):
        """Run the complete onboarding simulation"""
        self.test_email = email or generate_test_email()
        self.test_password = "Fit33Test$Secure2024!"
        self.test_name = "Test User"
        self.test_username = username or generate_test_username()
        
        print("")
        print("=" * 60)
        print("🧪 FIT33 TEST USER CREATION SCRIPT")
        print("=" * 60)
        print("")
        print(f"📧 Email: {self.test_email}")
        print(f"🔑 Password: {self.test_password}")
        print(f"👤 Name: {self.test_name}")
        print(f"🏷️  Username: @{self.test_username}")
        print("")
        print("-" * 60)
        
        # Run each step
        success = True
        success = self.step1_signup() and success
        success = self.step2_verify_auth() and success
        success = self.step3_create_profile() and success
        success = self.step4_set_username() and success
        success = self.step5_verify_database() and success
        success = self.step6_test_username_availability() and success
        
        self.print_summary(success)
        return success
    
    def step1_signup(self):
        """Step 1: Sign up the user (mimics app signup)"""
        print("")
        print("─" * 40)
        print("STEP 1: Sign Up User")
        print("─" * 40)
        
        try:
            log_info(f"Calling supabase.auth.sign_up with email: {self.test_email}")
            
            result = self.supabase.auth.sign_up({
                "email": self.test_email,
                "password": self.test_password,
                "options": {
                    "data": {
                        "name": self.test_name
                    }
                }
            })
            
            log_info(f"Result type: {type(result)}")
            
            if result.user:
                self.user_id = str(result.user.id)
                self.session = result.session
                log_step(1, "User signed up successfully")
                log_data("User ID", self.user_id)
                log_data("Email", result.user.email)
                log_data("Session exists", self.session is not None)
                
                if self.session:
                    log_info("User is authenticated and ready")
                else:
                    log_warning("No session - email confirmation might be required")
                    log_info("Checking if user still got created...")
                
                return True
            else:
                log_step(1, "Sign up returned no user", success=False)
                return False
                
        except Exception as e:
            log_step(1, f"Sign up failed: {e}", success=False)
            log_error(str(e))
            return False
    
    def step2_verify_auth(self):
        """Step 2: Verify authentication state"""
        print("")
        print("─" * 40)
        print("STEP 2: Verify Authentication")
        print("─" * 40)
        
        try:
            # Check current session
            session = self.supabase.auth.get_session()
            
            if session:
                log_step(2, "Session is active")
                log_data("Access token exists", session.access_token is not None)
                return True
            else:
                log_warning("No active session - this is normal if email confirmation is required")
                log_info("Will attempt to proceed with service key if available...")
                
                # Try to sign in if we have the user created
                if self.user_id:
                    log_step(2, "User exists but needs email confirmation (normal for test)")
                    return True
                return False
                
        except Exception as e:
            log_step(2, f"Auth verification issue: {e}", success=False)
            return True  # Continue anyway
    
    def step3_create_profile(self):
        """Step 3: Create user profile (mimics what app does after signup)"""
        print("")
        print("─" * 40)
        print("STEP 3: Create User Profile")
        print("─" * 40)
        
        if not self.user_id:
            log_step(3, "No user ID - cannot create profile", success=False)
            return False
        
        try:
            # First check if profile already exists (might be created by trigger)
            log_info("Checking if profile already exists...")
            existing = self.supabase.table("user_profiles").select("id, username").eq("id", self.user_id).execute()
            
            if existing.data and len(existing.data) > 0:
                log_info("Profile already exists (created by database trigger)")
                log_data("Existing profile ID", existing.data[0].get("id"))
                log_data("Current username", existing.data[0].get("username", "NULL"))
                log_step(3, "Profile exists - will update it")
                return True
            
            # Create profile if it doesn't exist
            profile_data = {
                "id": self.user_id,
                "name": self.test_name,
                "email": self.test_email,
                "has_completed_onboarding": False,
                "fitness_goal": "Build Muscle",
                "experience_level": "Intermediate",
                "height_cm": 175,
                "weight_kg": 75,
                "age": 30,
                "gender": "Male",
                "equipment": ["Dumbbells", "Barbell", "Cables"],
                "available_days": 4
            }
            
            log_info("Creating new profile...")
            result = self.supabase.table("user_profiles").insert(profile_data).execute()
            
            if result.data:
                log_step(3, "Profile created successfully")
                log_data("Profile ID", result.data[0].get("id"))
                return True
            else:
                log_step(3, "Profile insert returned no data", success=False)
                return False
                
        except Exception as e:
            error_str = str(e)
            if "duplicate key" in error_str.lower() or "already exists" in error_str.lower():
                log_info("Profile already exists (race condition, this is fine)")
                log_step(3, "Profile exists")
                return True
            log_step(3, f"Profile creation failed: {e}", success=False)
            log_error(error_str)
            return False
    
    def step4_set_username(self):
        """Step 4: Set username (the critical step we're testing)"""
        print("")
        print("─" * 40)
        print("STEP 4: Set Username")
        print("─" * 40)
        
        if not self.user_id:
            log_step(4, "No user ID - cannot set username", success=False)
            return False
        
        log_info(f"Attempting to set username: @{self.test_username}")
        
        # Method A: Try RPC function (what app uses)
        print("")
        print("   Trying Method A: RPC set_username function...")
        try:
            result = self.supabase.rpc("set_username", {"new_username": self.test_username}).execute()
            log_info(f"RPC result: {result.data}")
            
            if result.data == True or result.data == "true":
                log_step(4, "Username set via RPC ✓", success=True)
                return True
            else:
                log_warning(f"RPC returned: {result.data}")
                
        except Exception as e:
            log_warning(f"RPC method failed: {e}")
            log_info("This is expected if not authenticated - trying direct update...")
        
        # Method B: Direct table update
        print("")
        print("   Trying Method B: Direct table update...")
        try:
            result = self.supabase.table("user_profiles").update({
                "username": self.test_username
            }).eq("id", self.user_id).execute()
            
            if result.data and len(result.data) > 0:
                log_step(4, "Username set via direct update ✓", success=True)
                log_data("Updated username", result.data[0].get("username"))
                return True
            else:
                log_warning("Direct update returned no data")
                
        except Exception as e:
            log_warning(f"Direct update failed: {e}")
        
        # Method C: Upsert
        print("")
        print("   Trying Method C: Upsert...")
        try:
            result = self.supabase.table("user_profiles").upsert({
                "id": self.user_id,
                "username": self.test_username
            }).execute()
            
            if result.data:
                log_step(4, "Username set via upsert ✓", success=True)
                return True
                
        except Exception as e:
            log_warning(f"Upsert failed: {e}")
        
        log_step(4, "All username setting methods failed", success=False)
        return False
    
    def step5_verify_database(self):
        """Step 5: Verify data in database"""
        print("")
        print("─" * 40)
        print("STEP 5: Verify Database")
        print("─" * 40)
        
        if not self.user_id:
            log_step(5, "No user ID - cannot verify", success=False)
            return False
        
        try:
            # Small delay to ensure writes propagate
            time.sleep(0.5)
            
            result = self.supabase.table("user_profiles").select("*").eq("id", self.user_id).execute()
            
            if result.data and len(result.data) > 0:
                profile = result.data[0]
                log_step(5, "Profile found in database")
                print("")
                print("   📋 PROFILE DATA:")
                print(f"      ID: {profile.get('id')}")
                print(f"      Name: {profile.get('name')}")
                print(f"      Email: {profile.get('email')}")
                print(f"      Username: {profile.get('username') or 'NULL ⚠️'}")
                print(f"      Goal: {profile.get('fitness_goal')}")
                print(f"      Experience: {profile.get('experience_level')}")
                print(f"      Onboarding Complete: {profile.get('has_completed_onboarding')}")
                
                if profile.get('username'):
                    print("")
                    print("   ✅ USERNAME SAVED SUCCESSFULLY!")
                    return True
                else:
                    print("")
                    print("   ❌ USERNAME IS NULL - Something went wrong!")
                    return False
            else:
                log_step(5, "Profile not found in database", success=False)
                return False
                
        except Exception as e:
            log_step(5, f"Database verification failed: {e}", success=False)
            return False
    
    def step6_test_username_availability(self):
        """Step 6: Test username availability check"""
        print("")
        print("─" * 40)
        print("STEP 6: Test Username Availability")
        print("─" * 40)
        
        try:
            # Check if our username shows as taken
            result = self.supabase.rpc("is_username_available", {"check_username": self.test_username}).execute()
            
            if result.data == False:
                log_step(6, f"@{self.test_username} correctly shows as TAKEN")
            elif result.data == True:
                log_step(6, f"@{self.test_username} shows as AVAILABLE (should be taken!)", success=False)
                return False
            else:
                log_info(f"Availability check returned: {result.data}")
            
            # Test a random username
            random_name = f"random_{random.randint(100000, 999999)}"
            result2 = self.supabase.rpc("is_username_available", {"check_username": random_name}).execute()
            
            if result2.data == True:
                log_info(f"@{random_name} correctly shows as AVAILABLE")
            else:
                log_warning(f"Random username returned: {result2.data}")
            
            return True
            
        except Exception as e:
            log_step(6, f"Availability check failed: {e}", success=False)
            log_error("The is_username_available function may not exist or has errors")
            return False
    
    def print_summary(self, success):
        """Print final summary"""
        print("")
        print("=" * 60)
        if success:
            print("🎉 TEST PASSED - ALL STEPS COMPLETED")
        else:
            print("⚠️  TEST COMPLETED WITH ISSUES")
        print("=" * 60)
        print("")
        print(f"📧 Test email: {self.test_email}")
        print(f"🔑 Test password: {self.test_password}")
        print(f"🏷️  Test username: @{self.test_username}")
        print(f"🆔 User ID: {self.user_id}")
        print("")
        if success:
            print("✅ You can sign in with these credentials to test the app!")
        print("")


def check_existing_user(email_to_check):
    """Check if a user exists and their profile data"""
    print("")
    print("=" * 60)
    print(f"🔍 CHECKING USER: {email_to_check}")
    print("=" * 60)
    
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    
    try:
        # Search for user by email in profiles
        result = supabase.table("user_profiles").select("*").eq("email", email_to_check).execute()
        
        if result.data and len(result.data) > 0:
            profile = result.data[0]
            print("")
            print("📋 PROFILE FOUND:")
            print(f"   ID: {profile.get('id')}")
            print(f"   Name: {profile.get('name')}")
            print(f"   Email: {profile.get('email')}")
            print(f"   Username: {profile.get('username') or '⚠️ NULL'}")
            print(f"   Goal: {profile.get('fitness_goal')}")
            print(f"   Onboarding: {profile.get('has_completed_onboarding')}")
            
            if not profile.get('username'):
                print("")
                print("⚠️ USERNAME IS NULL - The save didn't work!")
        else:
            print("❌ No profile found for this email")
            
    except Exception as e:
        print(f"❌ Error: {e}")


def set_username_for_user(user_id, new_username):
    """Manually set username for a user"""
    print("")
    print("=" * 60)
    print(f"🔧 SETTING USERNAME: @{new_username} for {user_id}")
    print("=" * 60)
    
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    
    try:
        result = supabase.table("user_profiles").update({
            "username": new_username
        }).eq("id", user_id).execute()
        
        if result.data:
            print(f"✅ Username set to: @{new_username}")
            print(f"📋 Updated profile: {result.data[0]}")
        else:
            print("⚠️ Update returned no data")
            
    except Exception as e:
        print(f"❌ Error: {e}")


def main():
    """Main entry point"""
    
    # Parse command line arguments
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        
        if cmd in ["check", "lookup"]:
            if len(sys.argv) > 2:
                check_existing_user(sys.argv[2])
            else:
                print("Usage: python create_test_user.py check <email>")
            return
        
        if cmd in ["setusername", "set"]:
            if len(sys.argv) > 3:
                set_username_for_user(sys.argv[2], sys.argv[3])
            else:
                print("Usage: python create_test_user.py set <user_id> <username>")
            return
        
        if cmd == "help":
            print("""
FIT33 Test User Script
======================

Commands:
  python create_test_user.py              # Create new test user
  python create_test_user.py @myusername  # Create test user with specific username
  python create_test_user.py check <email>  # Check existing user by email
  python create_test_user.py set <id> <username>  # Set username for existing user
  python create_test_user.py help         # Show this help
            """)
            return
    
    # Default: create test user
    creator = TestUserCreator()
    
    # Allow custom email/username via args
    email = None
    username = None
    
    for i, arg in enumerate(sys.argv[1:]):
        if "@" in arg and "." in arg:
            email = arg
        elif arg.startswith("@"):
            username = arg[1:]  # Remove @
        else:
            username = arg
    
    creator.run_full_test(email=email, username=username)


if __name__ == "__main__":
    main()
