#!/usr/bin/env python3
"""
Comprehensive Auto-Gen Test Runner
This script helps run the Swift test harness and converts the markdown report to PDF
"""

import subprocess
import os
import sys
from datetime import datetime
from pathlib import Path

def print_banner():
    print("=" * 80)
    print(" " * 20 + "🏋️  COMPREHENSIVE AUTO-GEN TEST RUNNER")
    print("=" * 80)
    print()

def print_info(message):
    print(f"ℹ️  {message}")

def print_success(message):
    print(f"✅ {message}")

def print_error(message):
    print(f"❌ {message}")

def print_warning(message):
    print(f"⚠️  {message}")

def check_dependencies():
    """Check if required dependencies are installed"""
    print_info("Checking dependencies...")
    
    # Check for markdown to PDF converter
    try:
        result = subprocess.run(['which', 'pandoc'], capture_output=True, text=True)
        if result.returncode == 0:
            print_success("pandoc found")
            return True
    except:
        pass
    
    try:
        result = subprocess.run(['which', 'mdpdf'], capture_output=True, text=True)
        if result.returncode == 0:
            print_success("mdpdf found")
            return True
    except:
        pass
    
    print_warning("No markdown to PDF converter found")
    print_info("To generate PDF reports, install one of:")
    print_info("  - pandoc: brew install pandoc")
    print_info("  - mdpdf: pip install mdpdf")
    print()
    return False

def find_xcode_project():
    """Find the Xcode project file"""
    project_path = Path("/Users/josephreed/Desktop/Workout App")
    xcodeproj = list(project_path.glob("*.xcodeproj"))
    
    if xcodeproj:
        print_success(f"Found Xcode project: {xcodeproj[0].name}")
        return xcodeproj[0]
    else:
        print_error("Could not find Xcode project")
        return None

def build_and_run_tests():
    """Build and run the Swift test harness"""
    print()
    print_info("Building test harness...")
    print_warning("Note: The test harness needs to be run from within the iOS app")
    print()
    print("=" * 80)
    print("INSTRUCTIONS TO RUN THE TEST:")
    print("=" * 80)
    print()
    print("1. Open the project in Xcode:")
    print("   $ cd '/Users/josephreed/Desktop/Workout App'")
    print("   $ open GoFit.xcodeproj")
    print()
    print("2. Add ComprehensiveAutoGenTestView to your app:")
    print("   - Find ComprehensiveAutoGenTestHarness.swift in Project Navigator")
    print("   - In your DashboardView or SettingsView, add a button:")
    print()
    print("   NavigationLink(\"Run Auto-Gen Test\") {")
    print("       ComprehensiveAutoGenTestView()")
    print("   }")
    print()
    print("3. Run the app (⌘+R) and tap the \"Run Auto-Gen Test\" button")
    print()
    print("4. The test will:")
    print("   - Generate 20 diverse test users")
    print("   - Create 2-3 workouts per user (50+ total workouts)")
    print("   - Audit each workout against 8 comprehensive criteria")
    print("   - Save a detailed markdown report to Documents folder")
    print()
    print("5. After the test completes, run this script again to convert")
    print("   the markdown report to PDF")
    print()
    print("=" * 80)
    print()

def find_latest_report():
    """Find the latest test report markdown file"""
    documents_dir = Path.home() / "Library" / "Developer" / "CoreSimulator" / "Devices"
    
    # Try to find the report in the app's documents directory
    report_files = []
    
    # Also check the project directory
    project_dir = Path("/Users/josephreed/Desktop/Workout App")
    report_files.extend(project_dir.glob("AutoGen_Comprehensive_Test_Report_*.md"))
    
    if report_files:
        # Get the most recent report
        latest_report = max(report_files, key=lambda p: p.stat().st_mtime)
        return latest_report
    
    return None

def convert_markdown_to_pdf(markdown_file):
    """Convert markdown report to PDF"""
    if not markdown_file.exists():
        print_error(f"Report file not found: {markdown_file}")
        return False
    
    print_info(f"Converting {markdown_file.name} to PDF...")
    
    pdf_file = markdown_file.with_suffix('.pdf')
    
    # Try pandoc first
    try:
        result = subprocess.run([
            'pandoc',
            str(markdown_file),
            '-o', str(pdf_file),
            '--pdf-engine=pdflatex',
            '-V', 'geometry:margin=1in',
            '-V', 'fontsize=11pt'
        ], capture_output=True, text=True, timeout=60)
        
        if result.returncode == 0 and pdf_file.exists():
            print_success(f"PDF generated: {pdf_file}")
            return True
        else:
            print_error(f"pandoc failed: {result.stderr}")
    except FileNotFoundError:
        pass
    except subprocess.TimeoutExpired:
        print_error("PDF generation timed out")
    
    # Try mdpdf
    try:
        result = subprocess.run([
            'mdpdf',
            str(markdown_file),
            '-o', str(pdf_file)
        ], capture_output=True, text=True, timeout=60)
        
        if result.returncode == 0 and pdf_file.exists():
            print_success(f"PDF generated: {pdf_file}")
            return True
        else:
            print_error(f"mdpdf failed: {result.stderr}")
    except FileNotFoundError:
        pass
    except subprocess.TimeoutExpired:
        print_error("PDF generation timed out")
    
    print_warning("Could not convert to PDF. Install pandoc or mdpdf.")
    print_info(f"Markdown report is available at: {markdown_file}")
    return False

def main():
    print_banner()
    
    has_pdf_converter = check_dependencies()
    
    print()
    find_xcode_project()
    
    print()
    build_and_run_tests()
    
    # Check if there's an existing report to convert
    latest_report = find_latest_report()
    
    if latest_report:
        print()
        print_info(f"Found existing report: {latest_report.name}")
        
        if has_pdf_converter:
            response = input("Convert to PDF? (y/n): ").strip().lower()
            if response == 'y':
                convert_markdown_to_pdf(latest_report)
        else:
            print_info(f"Report available at: {latest_report}")
    
    print()
    print("=" * 80)
    print("✅ Setup complete!")
    print("=" * 80)
    print()

if __name__ == "__main__":
    main()

