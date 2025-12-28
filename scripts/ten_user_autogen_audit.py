#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════════════════════════
10 USER AUTO-GEN WORKOUT AUDIT
═══════════════════════════════════════════════════════════════════════════════

Creates 10 diverse test users with different profiles and goals, generates 
auto-gen workouts for each using the REAL workout generation logic, and
outputs a clean PDF report.

NO FAKE DATA - Uses actual exercise database and real selection logic.

Author: Fit33 Audit System
Date: December 2024
"""

import os
import sys
import random
from datetime import datetime
from typing import List, Dict, Optional

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import from comprehensive audit
from comprehensive_autogen_audit import (
    supabase,
    fetch_exercises_from_supabase,
    UserProfile,
    ExperienceLevel,
    FitnessGoal,
    WorkoutLocation,
    BodyType,
    Gender,
    Injury,
    select_exercises_for_workout,
    classify_movement_pattern,
)

# PDF Generation
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.units import inch

# ═══════════════════════════════════════════════════════════════════════════════
# 10 DIVERSE USER PROFILES - MANUALLY CRAFTED FOR VARIETY
# ═══════════════════════════════════════════════════════════════════════════════

def create_ten_diverse_users() -> List[UserProfile]:
    """
    Creates 10 unique user profiles with maximum diversity:
    - Different genders, ages, experience levels
    - Different goals
    - Different equipment access
    - Different limitations
    - Different workout counts (foundational vs experienced)
    """
    profiles = []
    
    # USER 1: Complete Beginner - First Week
    profiles.append(UserProfile(
        id=1,
        name="Alex Rivera",
        age=28,
        gender=Gender.MALE,
        weight_lbs=175,
        height_inches=70,
        body_type=BodyType.ECTOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[],
        workouts_completed=2,  # FOUNDATIONAL MODE
        preferred_workout_duration=40,
        available_days_per_week=4,
        notes="Complete beginner - testing foundational mode"
    ))
    
    # USER 2: Female Intermediate - Fat Loss Focus
    profiles.append(UserProfile(
        id=2,
        name="Sarah Chen",
        age=34,
        gender=Gender.FEMALE,
        weight_lbs=145,
        height_inches=65,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells", "Barbell"],
        injuries=[],
        workouts_completed=45,
        preferred_workout_duration=45,
        available_days_per_week=4,
        notes="Fat loss focus - wants toned physique"
    ))
    
    # USER 3: Advanced Male - Strength Focus
    profiles.append(UserProfile(
        id=3,
        name="Marcus Thompson",
        age=32,
        gender=Gender.MALE,
        weight_lbs=205,
        height_inches=73,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.GET_STRONGER,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebells"],
        injuries=[],
        workouts_completed=200,
        preferred_workout_duration=60,
        available_days_per_week=5,
        notes="Advanced lifter - max strength focus"
    ))
    
    # USER 4: Older Adult with Limitations
    profiles.append(UserProfile(
        id=4,
        name="Robert Williams",
        age=58,
        gender=Gender.MALE,
        weight_lbs=190,
        height_inches=69,
        body_type=BodyType.ENDOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.IMPROVE_HEALTH,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables"],
        injuries=[
            Injury("Lower Back", "be_careful", "Chronic lower back pain"),
            Injury("Knees", "be_careful", "Mild arthritis")
        ],
        workouts_completed=80,
        preferred_workout_duration=40,
        available_days_per_week=3,
        notes="Older adult with joint concerns - safety priority"
    ))
    
    # USER 5: Young Female - Stay Active
    profiles.append(UserProfile(
        id=5,
        name="Emily Davis",
        age=24,
        gender=Gender.FEMALE,
        weight_lbs=130,
        height_inches=64,
        body_type=BodyType.ECTOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.STAY_ACTIVE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[],
        workouts_completed=8,  # Still in foundational
        preferred_workout_duration=35,
        available_days_per_week=3,
        notes="Young beginner - general fitness"
    ))
    
    # USER 6: Intermediate Female - Build Muscle
    profiles.append(UserProfile(
        id=6,
        name="Jessica Martinez",
        age=29,
        gender=Gender.FEMALE,
        weight_lbs=155,
        height_inches=66,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines"],
        injuries=[],
        workouts_completed=90,
        preferred_workout_duration=50,
        available_days_per_week=4,
        notes="Wants to build muscle - focused on glutes/legs"
    ))
    
    # USER 7: Male with Shoulder Limitation
    profiles.append(UserProfile(
        id=7,
        name="David Kim",
        age=42,
        gender=Gender.MALE,
        weight_lbs=185,
        height_inches=71,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells", "Barbell"],
        injuries=[
            Injury("Shoulders", "be_careful", "Previous rotator cuff strain")
        ],
        workouts_completed=65,
        preferred_workout_duration=45,
        available_days_per_week=4,
        notes="Shoulder sensitivity - needs safe pressing alternatives"
    ))
    
    # USER 8: Endurance Focus
    profiles.append(UserProfile(
        id=8,
        name="Amanda Johnson",
        age=31,
        gender=Gender.FEMALE,
        weight_lbs=140,
        height_inches=67,
        body_type=BodyType.ECTOMORPH,
        experience_level=ExperienceLevel.INTERMEDIATE,
        fitness_goal=FitnessGoal.BUILD_ENDURANCE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[],
        workouts_completed=55,
        preferred_workout_duration=45,
        available_days_per_week=4,
        notes="Runner looking to complement cardio with strength"
    ))
    
    # USER 9: Advanced Female - Get Stronger
    profiles.append(UserProfile(
        id=9,
        name="Nicole Brown",
        age=27,
        gender=Gender.FEMALE,
        weight_lbs=160,
        height_inches=68,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.GET_STRONGER,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebells"],
        injuries=[],
        workouts_completed=180,
        preferred_workout_duration=60,
        available_days_per_week=5,
        notes="Powerlifting background - wants strength gains"
    ))
    
    # USER 10: Beginner Male - Lose Weight
    profiles.append(UserProfile(
        id=10,
        name="Michael Garcia",
        age=38,
        gender=Gender.MALE,
        weight_lbs=225,
        height_inches=70,
        body_type=BodyType.ENDOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.LOSE_WEIGHT,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells"],
        injuries=[],
        workouts_completed=12,
        preferred_workout_duration=40,
        available_days_per_week=3,
        notes="Weight loss focus - new to structured training"
    ))
    
    return profiles

# ═══════════════════════════════════════════════════════════════════════════════
# WORKOUT TARGET SELECTION FOR EACH USER
# ═══════════════════════════════════════════════════════════════════════════════

def get_workout_targets_for_user(user: UserProfile) -> List[str]:
    """
    Select workout targets based on user's goal and profile.
    Returns a muscle group combination appropriate for the user.
    """
    goal = user.fitness_goal
    
    # Goal-based workout selection
    if goal == FitnessGoal.BUILD_MUSCLE:
        options = [
            ["Back", "Biceps"],
            ["Chest", "Triceps"],
            ["Shoulders", "Arms"],
            ["Legs", "Glutes"],
        ]
    elif goal == FitnessGoal.LOSE_WEIGHT:
        options = [
            ["Chest", "Back"],  # Upper body circuit
            ["Legs", "Core"],
            ["Full Body"],
            ["Push"],
        ]
    elif goal == FitnessGoal.GET_STRONGER:
        options = [
            ["Back", "Biceps"],
            ["Chest", "Shoulders"],
            ["Legs", "Glutes"],
            ["Push"],
        ]
    elif goal == FitnessGoal.STAY_ACTIVE:
        options = [
            ["Full Body"],
            ["Chest", "Back"],
            ["Legs", "Core"],
        ]
    elif goal == FitnessGoal.BUILD_ENDURANCE:
        options = [
            ["Legs", "Core"],
            ["Full Body"],
            ["Back", "Shoulders"],
        ]
    elif goal == FitnessGoal.IMPROVE_HEALTH:
        options = [
            ["Full Body"],
            ["Chest", "Back"],
            ["Legs", "Glutes"],
        ]
    else:
        options = [["Back", "Biceps"]]
    
    return random.choice(options)

# ═══════════════════════════════════════════════════════════════════════════════
# PDF GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

def generate_clean_pdf(users_data: List[Dict], output_path: str):
    """Generate a clean, well-formatted PDF report"""
    doc = SimpleDocTemplate(output_path, pagesize=letter, 
                           topMargin=0.5*inch, bottomMargin=0.5*inch,
                           leftMargin=0.5*inch, rightMargin=0.5*inch)
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle('Title', parent=styles['Heading1'], 
                                 fontSize=28, alignment=TA_CENTER, 
                                 spaceAfter=20, textColor=colors.darkblue)
    
    subtitle_style = ParagraphStyle('Subtitle', parent=styles['Normal'],
                                   fontSize=12, alignment=TA_CENTER,
                                   spaceAfter=30, textColor=colors.grey)
    
    user_header_style = ParagraphStyle('UserHeader', parent=styles['Heading2'],
                                       fontSize=18, textColor=colors.darkblue,
                                       spaceBefore=10, spaceAfter=10)
    
    workout_header_style = ParagraphStyle('WorkoutHeader', parent=styles['Heading3'],
                                         fontSize=14, textColor=colors.darkgreen,
                                         spaceBefore=15, spaceAfter=10)
    
    story = []
    
    # Title Page
    story.append(Spacer(1, 2*inch))
    story.append(Paragraph("10 USER AUTO-GEN", title_style))
    story.append(Paragraph("WORKOUT AUDIT REPORT", title_style))
    story.append(Spacer(1, 0.5*inch))
    story.append(Paragraph(f"Generated: {datetime.now().strftime('%B %d, %Y at %I:%M %p')}", subtitle_style))
    story.append(Paragraph("Using Real Exercise Database & Generation Logic", subtitle_style))
    story.append(PageBreak())
    
    # Table of Contents
    story.append(Paragraph("USERS TESTED", styles['Heading1']))
    story.append(Spacer(1, 10))
    
    toc_data = [["#", "Name", "Experience", "Goal", "Limitations"]]
    for user_data in users_data:
        user = user_data['user']
        limitations = "None"
        if user.injuries:
            limitations = ", ".join([f"{i.area}" for i in user.injuries])
        toc_data.append([
            str(user.id),
            user.name,
            user.experience_level.value,
            user.fitness_goal.value,
            limitations
        ])
    
    toc_table = Table(toc_data, colWidths=[30, 120, 90, 110, 120])
    toc_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.darkblue),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('ALIGN', (0, 0), (0, -1), 'CENTER'),
    ]))
    story.append(toc_table)
    story.append(PageBreak())
    
    # Individual User Reports
    for user_data in users_data:
        user = user_data['user']
        targets = user_data['targets']
        exercises = user_data['exercises']
        
        # User Header
        story.append(Paragraph(f"USER {user.id}: {user.name.upper()}", user_header_style))
        
        # Profile Table
        profile_data = [
            ["Age", str(user.age), "Gender", user.gender.value],
            ["Weight", f"{user.weight_lbs} lbs", "Height", f"{user.height_inches} in"],
            ["Experience", user.experience_level.value, "Body Type", user.body_type.value],
            ["Goal", user.fitness_goal.value, "Duration", f"{user.preferred_workout_duration} min"],
            ["Equipment", ", ".join(user.available_equipment[:3]), "Workouts", str(user.workouts_completed)],
        ]
        
        if user.injuries:
            profile_data.append(["Limitations", ", ".join([f"{i.area} ({i.severity})" for i in user.injuries]), "", ""])
        
        profile_table = Table(profile_data, colWidths=[80, 150, 80, 150])
        profile_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (0, -1), colors.Color(0.9, 0.9, 0.95)),
            ('BACKGROUND', (2, 0), (2, -1), colors.Color(0.9, 0.9, 0.95)),
            ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
            ('FONTNAME', (2, 0), (2, -1), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, -1), 9),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.lightgrey),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ]))
        story.append(profile_table)
        story.append(Spacer(1, 15))
        
        # Auto-Gen Input
        story.append(Paragraph("AUTO-GEN INPUT", workout_header_style))
        input_text = f"<b>Target Muscles:</b> {', '.join(targets)}"
        story.append(Paragraph(input_text, styles['Normal']))
        story.append(Spacer(1, 10))
        
        # Generated Workout
        foundational_mode = "YES" if user.workouts_completed < 10 else "NO"
        story.append(Paragraph(f"GENERATED WORKOUT (Foundational Mode: {foundational_mode})", workout_header_style))
        
        if exercises:
            ex_data = [["#", "Exercise Name", "Equipment", "Movement Pattern"]]
            for i, ex in enumerate(exercises, 1):
                pattern = classify_movement_pattern(ex.get('name', ''), ex.get('equipment', ''))
                ex_data.append([
                    str(i), 
                    ex.get('name', 'Unknown')[:45],  # Truncate long names
                    ex.get('equipment', 'Unknown'),
                    pattern
                ])
            
            ex_table = Table(ex_data, colWidths=[25, 220, 100, 100])
            ex_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.darkgreen),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
                ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, -1), 8),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                ('ALIGN', (0, 0), (0, -1), 'CENTER'),
            ]))
            story.append(ex_table)
        else:
            story.append(Paragraph("⚠️ No exercises generated - validation failed", styles['Normal']))
        
        story.append(Spacer(1, 10))
        
        # Notes
        if user.notes:
            story.append(Paragraph(f"<b>Notes:</b> {user.notes}", styles['Normal']))
        
        story.append(PageBreak())
    
    # Build PDF
    doc.build(story)
    print(f"\n📄 PDF saved to: {output_path}")

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    print("=" * 80)
    print("🏋️ 10 USER AUTO-GEN WORKOUT AUDIT")
    print("=" * 80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Load exercises from database
    print("📥 Loading exercises from Supabase...")
    all_exercises = []
    offset = 0
    batch_size = 1000
    
    while True:
        batch = fetch_exercises_from_supabase(batch_size, offset)
        if not batch:
            break
        all_exercises.extend(batch)
        offset += batch_size
        if len(batch) < batch_size:
            break
    
    print(f"✅ Loaded {len(all_exercises)} exercises from database")
    
    # Create 10 diverse users
    print("\n📋 Creating 10 diverse test user profiles...")
    users = create_ten_diverse_users()
    print(f"✅ Created {len(users)} user profiles")
    
    # Generate workouts for each user
    users_data = []
    
    for user in users:
        print(f"\n{'='*60}")
        print(f"USER {user.id}: {user.name}")
        print(f"{'='*60}")
        print(f"   Age: {user.age}, Gender: {user.gender.value}")
        print(f"   Experience: {user.experience_level.value}")
        print(f"   Goal: {user.fitness_goal.value}")
        print(f"   Workouts Completed: {user.workouts_completed}")
        print(f"   Equipment: {', '.join(user.available_equipment)}")
        if user.injuries:
            print(f"   ⚠️ Limitations: {', '.join([f'{i.area} ({i.severity})' for i in user.injuries])}")
        
        # Get workout targets for this user
        targets = get_workout_targets_for_user(user)
        print(f"\n   🎯 Generating workout for: {', '.join(targets)}")
        
        # Expand targets for Push/Pull/Full Body
        expanded_targets = targets.copy()
        if "Push" in targets:
            expanded_targets = ["Chest", "Shoulders", "Triceps"]
        elif "Pull" in targets:
            expanded_targets = ["Back", "Biceps", "Rear Delts"]
        elif "Full Body" in targets:
            expanded_targets = ["Chest", "Back", "Shoulders", "Legs", "Core"]
        
        # Generate workout using REAL selection logic
        selected = select_exercises_for_workout(
            exercises=all_exercises,
            target_muscles=expanded_targets,
            user=user,
            count=6  # Standard 6 exercises
        )
        
        print(f"   ✅ Generated {len(selected)} exercises")
        
        for i, ex in enumerate(selected, 1):
            pattern = classify_movement_pattern(ex.get('name', ''), ex.get('equipment', ''))
            print(f"      {i}. {ex.get('name', 'Unknown')} ({ex.get('equipment', '')}) [{pattern}]")
        
        users_data.append({
            'user': user,
            'targets': targets,
            'expanded_targets': expanded_targets,
            'exercises': selected
        })
    
    # Generate PDF
    print("\n" + "=" * 80)
    print("📄 GENERATING PDF REPORT")
    print("=" * 80)
    
    output_path = "/Users/josephreed/Desktop/Workout App/Ten_User_AutoGen_Audit.pdf"
    generate_clean_pdf(users_data, output_path)
    
    print("\n✅ AUDIT COMPLETE!")
    print(f"   Users tested: {len(users)}")
    print(f"   Total exercises generated: {sum(len(u['exercises']) for u in users_data)}")
    print(f"   PDF saved to: {output_path}")

if __name__ == "__main__":
    main()
