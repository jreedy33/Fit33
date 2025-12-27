#!/usr/bin/env python3
"""
Limitation Filter System Report Generator

Generates a comprehensive PDF report documenting the new metadata-driven
Limitation/Injury Filtering System for the Fit33 app.

Usage: python generate_limitation_filter_report.py
"""

from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.colors import HexColor
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, 
    PageBreak, ListFlowable, ListItem
)
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from datetime import datetime

def create_report():
    """Generate the comprehensive limitation filter system report."""
    
    filename = "/Users/josephreed/Desktop/Workout App/Limitation_Filter_System_Report.pdf"
    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        rightMargin=0.75*inch,
        leftMargin=0.75*inch,
        topMargin=0.75*inch,
        bottomMargin=0.75*inch
    )
    
    # Styles
    styles = getSampleStyleSheet()
    
    title_style = ParagraphStyle(
        'Title',
        parent=styles['Heading1'],
        fontSize=24,
        textColor=HexColor('#1a1a2e'),
        spaceAfter=20,
        alignment=TA_CENTER
    )
    
    heading_style = ParagraphStyle(
        'Heading',
        parent=styles['Heading2'],
        fontSize=16,
        textColor=HexColor('#16213e'),
        spaceBefore=20,
        spaceAfter=10
    )
    
    subheading_style = ParagraphStyle(
        'SubHeading',
        parent=styles['Heading3'],
        fontSize=13,
        textColor=HexColor('#0f3460'),
        spaceBefore=15,
        spaceAfter=8
    )
    
    body_style = ParagraphStyle(
        'Body',
        parent=styles['Normal'],
        fontSize=10,
        textColor=HexColor('#333333'),
        spaceAfter=8,
        leading=14
    )
    
    code_style = ParagraphStyle(
        'Code',
        parent=styles['Code'],
        fontSize=8,
        fontName='Courier',
        textColor=HexColor('#2d3436'),
        backColor=HexColor('#f5f6fa'),
        spaceAfter=10,
        leftIndent=10,
        rightIndent=10
    )
    
    # Build document content
    story = []
    
    # Title
    story.append(Paragraph("Limitation/Injury Filtering System", title_style))
    story.append(Paragraph("Comprehensive Implementation Report", 
                          ParagraphStyle('Subtitle', fontSize=14, textColor=HexColor('#666'), 
                                        alignment=TA_CENTER, spaceAfter=10)))
    story.append(Paragraph(f"Generated: {datetime.now().strftime('%B %d, %Y at %I:%M %p')}", 
                          ParagraphStyle('Date', fontSize=10, textColor=HexColor('#888'), 
                                        alignment=TA_CENTER, spaceAfter=30)))
    
    # Executive Summary
    story.append(Paragraph("Executive Summary", heading_style))
    story.append(Paragraph(
        "This document details the implementation of a comprehensive, metadata-driven "
        "Limitation/Injury Filtering System for the Fit33 iOS fitness app. The system intelligently "
        "filters and scores exercises based on user-specified physical limitations (injuries, "
        "chronic conditions) without hardcoding specific exercise names. Instead, it uses "
        "exercise metadata tags to make filtering decisions that work for any exercise, "
        "including new ones added to the database.",
        body_style
    ))
    story.append(Spacer(1, 15))
    
    # Key Features
    story.append(Paragraph("Key Features", subheading_style))
    features = [
        "<b>Metadata-Driven:</b> No hardcoded exercise names - uses tags like spinal load, impact level, etc.",
        "<b>4 Severity Levels:</b> Skip Completely, Stretching Only, Light Work Only, Be Careful",
        "<b>9 Body Areas:</b> Lower Back, Shoulders, Knees, Hips, Neck, Wrists, Elbows, Ankles, Other",
        "<b>Comprehensive Rule Tables:</b> Area-specific rules for each severity level",
        "<b>Scoring Integration:</b> Penalties/boosts applied during exercise selection",
        "<b>Unit Tested:</b> 10 test cases covering all major scenarios",
        "<b>Backward Compatible:</b> Works with existing LimitationsService"
    ]
    for feature in features:
        story.append(Paragraph(f"• {feature}", body_style))
    
    story.append(PageBreak())
    
    # Architecture
    story.append(Paragraph("System Architecture", heading_style))
    story.append(Paragraph(
        "The system is composed of 5 new Swift files that work together to provide comprehensive "
        "limitation filtering:",
        body_style
    ))
    
    # File table
    files_data = [
        ["File", "Purpose", "Lines"],
        ["LimitationFilterEngine.swift", "Core models, enums, and filtering logic", "~400"],
        ["LimitationRuleTables.swift", "Area-specific rule definitions", "~500"],
        ["ExerciseMetadataClassifier.swift", "Intelligent exercise metadata derivation", "~350"],
        ["LimitationFilterIntegration.swift", "Integration with existing services", "~350"],
        ["LimitationFilterTests.swift", "Unit tests for all scenarios", "~550"]
    ]
    
    file_table = Table(files_data, colWidths=[2.2*inch, 3.2*inch, 0.8*inch])
    file_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HexColor('#1a1a2e')),
        ('TEXTCOLOR', (0, 0), (-1, 0), HexColor('#ffffff')),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('ALIGN', (2, 0), (2, -1), 'CENTER'),
        ('GRID', (0, 0), (-1, -1), 0.5, HexColor('#cccccc')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [HexColor('#ffffff'), HexColor('#f8f9fa')]),
        ('TOPPADDING', (0, 0), (-1, -1), 6),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
    ]))
    story.append(file_table)
    story.append(Spacer(1, 20))
    
    # Data Models
    story.append(Paragraph("Data Models", heading_style))
    
    story.append(Paragraph("LimitationArea Enum", subheading_style))
    story.append(Paragraph(
        "Defines the body areas that can have limitations:",
        body_style
    ))
    story.append(Paragraph(
        "lowerBack, shoulders, knees, hips, neck, wrists, elbows, ankles, upperBack, other",
        code_style
    ))
    
    story.append(Paragraph("LimitationSeverity Enum", subheading_style))
    severity_data = [
        ["Severity", "Behavior", "Score Impact"],
        ["Skip Completely", "Hard exclusion of exercises affecting area", "Exercise removed"],
        ["Stretching Only", "Only allow stretch/mobility exercises for area", "Exercise removed if not stretch"],
        ["Light Work Only", "Exclude heavy compounds, prefer machines", "±50-200 penalty/boost"],
        ["Be Careful", "Penalize risky, boost safe options", "±30-150 penalty/boost"]
    ]
    
    sev_table = Table(severity_data, colWidths=[1.3*inch, 3*inch, 1.9*inch])
    sev_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HexColor('#0f3460')),
        ('TEXTCOLOR', (0, 0), (-1, 0), HexColor('#ffffff')),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('GRID', (0, 0), (-1, -1), 0.5, HexColor('#cccccc')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [HexColor('#ffffff'), HexColor('#f8f9fa')]),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(sev_table)
    story.append(Spacer(1, 15))
    
    story.append(PageBreak())
    
    # Exercise Metadata
    story.append(Paragraph("Exercise Risk Metadata Tags", heading_style))
    story.append(Paragraph(
        "Each exercise is classified with these metadata tags, derived automatically by the "
        "ExerciseMetadataClassifier based on exercise name and equipment:",
        body_style
    ))
    
    metadata_data = [
        ["Tag", "Values", "Example Use"],
        ["spinalLoad", "none, low, moderate, high", "Lower back filtering"],
        ["axialLoading", "none, low, high", "Cervical spine protection"],
        ["unsupportedTorso", "true, false", "Bent-over row detection"],
        ["overheadWork", "none, partial, full", "Shoulder overhead exclusion"],
        ["kneeFlexionDepth", "low, moderate, high", "Deep squat filtering"],
        ["shoulderStressFlags", "uprightRow, behindNeck, etc.", "Dangerous shoulder patterns"],
        ["impactLevel", "none, low, moderate, high", "Plyometric filtering"],
        ["balanceDemand", "low, moderate, high", "Ankle stability"],
        ["isMachineSupported", "true, false", "Safe alternative preference"],
        ["isChestSupported", "true, false", "Back-safe row preference"],
        ["isStretchOrMobility", "true, false", "Stretching-only mode"],
        ["hipHingeDemand", "true, false", "Hip/back hinge detection"]
    ]
    
    meta_table = Table(metadata_data, colWidths=[1.4*inch, 2.2*inch, 2.6*inch])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HexColor('#16213e')),
        ('TEXTCOLOR', (0, 0), (-1, 0), HexColor('#ffffff')),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('GRID', (0, 0), (-1, -1), 0.5, HexColor('#cccccc')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [HexColor('#ffffff'), HexColor('#f8f9fa')]),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 20))
    
    # Area-Specific Rules
    story.append(Paragraph("Area-Specific Rule Tables", heading_style))
    
    story.append(Paragraph("Lower Back Rules", subheading_style))
    lb_rules = [
        "<b>Skip Completely:</b> High spinal load, high axial loading, unsupported hinge, unsupported bent-over row",
        "<b>Light Work Exclude:</b> High spinal load, unsupported hinge patterns",
        "<b>Light Work Prefer:</b> Machine (+50), chest-supported (+80), seated (+40), lying (+60)",
        "<b>Light Work Penalize:</b> Moderate spinal load (+100), unsupported torso (+150)",
        "<b>Be Careful Boost:</b> Machine (+30), chest-supported (+50), lying (+40)",
        "<b>Be Careful Penalize:</b> High spinal load (+150), unsupported torso (+80)"
    ]
    for rule in lb_rules:
        story.append(Paragraph(f"• {rule}", body_style))
    
    story.append(Paragraph("Shoulder Rules", subheading_style))
    sh_rules = [
        "<b>Skip Completely:</b> Full overhead, upright row pattern, behind neck, guillotine, heavy dip",
        "<b>Light Work Exclude:</b> Full overhead, heavy dip, behind-neck/guillotine/upright-row patterns",
        "<b>Light Work Prefer:</b> Machine (+50), cable work (+30)",
        "<b>Be Careful Penalize:</b> Upright row (+100), behind neck (+150), guillotine (+150), overhead (+60)"
    ]
    for rule in sh_rules:
        story.append(Paragraph(f"• {rule}", body_style))
    
    story.append(Paragraph("Knee Rules", subheading_style))
    kn_rules = [
        "<b>Skip Completely:</b> High knee flexion (deep squat), moderate+ impact, heavy squat/lunge",
        "<b>Light Work Exclude:</b> Deep flexion without machine support, moderate+ impact",
        "<b>Light Work Prefer:</b> Machine (+60), low flexion (+40), lying (+50)",
        "<b>Be Careful Penalize:</b> Impact (+120), deep flexion (+80), high balance (+60)"
    ]
    for rule in kn_rules:
        story.append(Paragraph(f"• {rule}", body_style))
    
    story.append(PageBreak())
    
    # Integration
    story.append(Paragraph("Integration with Workout Generation", heading_style))
    story.append(Paragraph(
        "The limitation filtering system integrates at two key points in the workout generation flow:",
        body_style
    ))
    
    story.append(Paragraph("1. Pre-Filtering (LimitationsService.filterSafeExercises)", subheading_style))
    story.append(Paragraph(
        "Before any exercise selection, the full exercise library is filtered to remove exercises "
        "that violate 'Skip Completely' or 'Stretching Only' limitations. This uses both the legacy "
        "keyword-based system and the new metadata-driven classifier for comprehensive coverage.",
        body_style
    ))
    
    story.append(Paragraph("2. Scoring (LimitationsService.getSafetyPenalty)", subheading_style))
    story.append(Paragraph(
        "During exercise scoring in WorkoutGeneratorService, each exercise receives a safety "
        "penalty or boost based on 'Light Work Only' and 'Be Careful' limitations. This allows "
        "the system to prefer safer alternatives without completely excluding exercises.",
        body_style
    ))
    
    story.append(Paragraph("Code Integration Example", subheading_style))
    story.append(Paragraph(
        "// In WorkoutGeneratorService.generateFromCoreData:\n"
        "// 1. Filter unsafe exercises first\n"
        "allExercises = LimitationsService.shared.filterSafeExercises(allExercises)\n\n"
        "// 2. Apply safety penalty during scoring\n"
        "let safetyPenalty = LimitationsService.shared.getSafetyPenalty(for: exercise)\n"
        "score -= safetyPenalty  // Positive penalty = decrease score",
        code_style
    ))
    story.append(Spacer(1, 20))
    
    # Unit Tests
    story.append(Paragraph("Unit Tests", heading_style))
    story.append(Paragraph(
        "The system includes comprehensive unit tests covering all major scenarios:",
        body_style
    ))
    
    test_data = [
        ["Test", "Description", "Assertions"],
        ["Lower Back Skip", "High spinal load excluded, machine/chest-supported allowed", "4"],
        ["Lower Back Light", "Heavy excluded, machine allowed, chest-supported boosted", "4"],
        ["Lower Back Careful", "Penalties for high load, boosts for safe options", "3"],
        ["Shoulder Skip", "Overhead, upright row, behind neck, dip, guillotine excluded", "5"],
        ["Shoulder Careful", "Dangerous patterns penalized, machines boosted", "2"],
        ["Knee Skip", "Deep flexion and impact excluded, machine isolation allowed", "3"],
        ["Stretching Only", "Non-stretch excluded, stretch allowed", "2"],
        ["Multiple Limitations", "All limitations applied, skip wins over careful", "2"],
        ["Equipment Cap", "Foundational ≤2, short workout ≤2, long workout ≥4", "3"],
        ["Metadata Classification", "Deadlift, machine row, OHP, stretch correctly classified", "4"]
    ]
    
    test_table = Table(test_data, colWidths=[1.5*inch, 3.5*inch, 0.8*inch])
    test_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), HexColor('#1a1a2e')),
        ('TEXTCOLOR', (0, 0), (-1, 0), HexColor('#ffffff')),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8),
        ('GRID', (0, 0), (-1, -1), 0.5, HexColor('#cccccc')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [HexColor('#ffffff'), HexColor('#f8f9fa')]),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('ALIGN', (2, 0), (2, -1), 'CENTER'),
    ]))
    story.append(test_table)
    
    story.append(PageBreak())
    
    # User Flow
    story.append(Paragraph("User Flow", heading_style))
    
    story.append(Paragraph("Setting Limitations", subheading_style))
    story.append(Paragraph(
        "Users can set limitations during onboarding or in Settings → Limitations:\n\n"
        "1. Select Affected Area (Lower Back, Shoulders, Knees, etc.)\n"
        "2. Choose Accommodation Level:\n"
        "   • Skip completely - Don't recommend ANY exercises for this area\n"
        "   • Light work only - Light exercises OK, skip heavy compounds\n"
        "   • Stretching only - Only stretching/mobility for this area\n"
        "   • Be careful - Can do exercises, prefer safer options\n"
        "3. Optionally add notes\n"
        "4. Save - limitations apply immediately to all future workouts",
        body_style
    ))
    
    story.append(Paragraph("During Workout Generation", subheading_style))
    story.append(Paragraph(
        "When generating a Quick Workout:\n\n"
        "1. User selects duration, muscle groups, focus areas, equipment\n"
        "2. System fetches all matching exercises from database\n"
        "3. LimitationsService.filterSafeExercises removes hard exclusions\n"
        "4. Remaining exercises are scored with safety penalties/boosts\n"
        "5. Top-scored exercises are selected\n"
        "6. If limitations caused substitutions, user sees a note:\n"
        "   \"Adjusted to respect your Lower Back setting\"",
        body_style
    ))
    story.append(Spacer(1, 20))
    
    # Example Scenarios
    story.append(Paragraph("Example Scenarios", heading_style))
    
    story.append(Paragraph("Scenario 1: Lower Back Injury - Skip Completely", subheading_style))
    story.append(Paragraph(
        "User: Has a herniated disc, selects 'Skip completely' for Lower Back\n"
        "Result: Deadlifts, bent-over rows, good mornings, heavy squats are excluded\n"
        "Alternatives: Machine rows, chest-supported rows, leg press are prioritized",
        body_style
    ))
    
    story.append(Paragraph("Scenario 2: Shoulder Tendinitis - Be Careful", subheading_style))
    story.append(Paragraph(
        "User: Recovering from shoulder tendinitis, selects 'Be careful' for Shoulders\n"
        "Result: Upright rows and behind-neck exercises heavily penalized (-100 to -150)\n"
        "Machine presses and cable exercises get boost (+30)\n"
        "Workout still includes pressing movements but prefers safer variations",
        body_style
    ))
    
    story.append(Paragraph("Scenario 3: Knee Surgery Recovery - Light Work Only", subheading_style))
    story.append(Paragraph(
        "User: 3 months post knee surgery, selects 'Light work only' for Knees\n"
        "Result: Deep squats and plyometrics excluded\n"
        "Leg press, seated leg curl, step-ups allowed with preference for machines\n"
        "High-balance movements penalized",
        body_style
    ))
    
    story.append(PageBreak())
    
    # Future Enhancements
    story.append(Paragraph("Future Enhancements", heading_style))
    story.append(Paragraph(
        "The metadata-driven architecture enables easy expansion:",
        body_style
    ))
    
    future_items = [
        "<b>Database-stored metadata:</b> Add columns to exercises table for cached metadata",
        "<b>User override rules:</b> Allow users to mark specific exercises as safe/unsafe for them",
        "<b>Progressive recovery:</b> Suggest moving from 'Skip' to 'Light' to 'Careful' over time",
        "<b>Physical therapist integration:</b> Allow PTs to set client-specific limitations",
        "<b>Smart alternatives:</b> Suggest specific safe alternatives when excluding exercises",
        "<b>Warning UI:</b> Show caution badges on exercises during workout",
        "<b>History learning:</b> Track which exercises user swaps out to learn preferences"
    ]
    for item in future_items:
        story.append(Paragraph(f"• {item}", body_style))
    
    story.append(Spacer(1, 30))
    
    # Conclusion
    story.append(Paragraph("Conclusion", heading_style))
    story.append(Paragraph(
        "The new Limitation/Injury Filtering System provides comprehensive, intelligent protection "
        "for users with physical limitations. By using metadata-driven rules rather than hardcoded "
        "exercise lists, the system:\n\n"
        "• Works with ALL exercises, including future additions\n"
        "• Respects user preferences (Skip/Light/Stretch/Careful)\n"
        "• Prefers safe alternatives over exclusion when possible\n"
        "• Is fully tested with unit tests\n"
        "• Integrates seamlessly with existing workout generation\n\n"
        "Users can now confidently generate workouts knowing the app will respect their physical "
        "limitations and prioritize their safety.",
        body_style
    ))
    
    # Build PDF
    doc.build(story)
    print(f"✅ Report generated: {filename}")
    return filename

if __name__ == "__main__":
    create_report()
