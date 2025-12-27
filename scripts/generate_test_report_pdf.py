#!/usr/bin/env python3
"""
Generate PDF Report for Auto-Gen Workout Test Results
"""

import json
from fpdf import FPDF
from datetime import datetime

class PDF(FPDF):
    def header(self):
        self.set_font('Helvetica', 'B', 12)
        self.cell(0, 10, 'Auto-Gen Workout Test Report', 0, 1, 'C')
        self.ln(5)
    
    def footer(self):
        self.set_y(-15)
        self.set_font('Helvetica', 'I', 8)
        self.cell(0, 10, f'Page {self.page_no()}', 0, 0, 'C')

# Load test results
with open('autogen_test_results.json', 'r') as f:
    data = json.load(f)

# Create PDF
pdf = PDF()
pdf.set_auto_page_break(auto=True, margin=15)

# Title Page
pdf.add_page()
pdf.set_font('Helvetica', 'B', 24)
pdf.cell(0, 20, '', 0, 1)
pdf.cell(0, 15, 'Auto-Gen Workout', 0, 1, 'C')
pdf.cell(0, 15, 'Test Results Report', 0, 1, 'C')
pdf.ln(20)

pdf.set_font('Helvetica', '', 14)
pdf.cell(0, 10, f'Generated: {datetime.now().strftime("%B %d, %Y")}', 0, 1, 'C')
pdf.cell(0, 10, f'Total Tests: {data["summary"]["total_tests"]}', 0, 1, 'C')
pdf.cell(0, 10, f'Overall Grade: {data["summary"]["overall_grade"]}', 0, 1, 'C')

# Summary Page
pdf.add_page()
pdf.set_font('Helvetica', 'B', 18)
pdf.cell(0, 10, 'Executive Summary', 0, 1)
pdf.ln(5)

pdf.set_font('Helvetica', 'B', 12)
pdf.cell(0, 8, 'Grade Distribution:', 0, 1)
pdf.set_font('Helvetica', '', 11)
for grade, count in sorted(data['summary']['grades'].items()):
    pct = (count / data['summary']['total_tests']) * 100
    pdf.cell(0, 6, f'  Grade {grade}: {count} tests ({pct:.1f}%)', 0, 1)

pdf.ln(5)
pdf.set_font('Helvetica', 'B', 12)
pdf.cell(0, 8, 'Average Scores:', 0, 1)
pdf.set_font('Helvetica', '', 11)
for metric, score in data['summary']['avg_scores'].items():
    metric_name = metric.replace('_', ' ').title()
    pdf.cell(0, 6, f'  {metric_name}: {score:.1f}%', 0, 1)

# Grading Methodology
pdf.add_page()
pdf.set_font('Helvetica', 'B', 18)
pdf.cell(0, 10, 'Grading Methodology', 0, 1)
pdf.ln(5)

pdf.set_font('Helvetica', '', 11)
methodology = """Each workout is graded on 4 metrics with weighted average:

1. EQUIPMENT ACCURACY (35% weight)
   - Measures: Do ALL exercises match user's selected equipment?
   - 100% = all exercises use correct equipment
   - 0% = no exercises match equipment

2. MUSCLE ACCURACY (30% weight)
   - Measures: Do exercises target the user's selected muscles?
   - Checks primary_muscles field against user selection
   - Uses muscle group expansion (e.g., "Back" includes Lats, Upper Back, Lower Back)

3. VARIETY (20% weight)
   - Measures: Are exercises diverse (no repetitive/similar exercises)?
   - Penalizes duplicate exercise names
   - Penalizes overuse of same equipment type

4. QUALITY (15% weight)
   - Measures: Overall workout structure
   - Checks minimum exercise count (5 recommended)
   - Checks workout type matches user's fitness goal

FORMULA:
Overall = (Equipment x 0.35) + (Muscle x 0.30) + (Variety x 0.20) + (Quality x 0.15)

GRADE SCALE:
A = 90-100%  |  B = 80-89%  |  C = 70-79%  |  D = 60-69%  |  F = <60%
"""

for line in methodology.split('\n'):
    pdf.cell(0, 5, line, 0, 1)

# Detailed Results
pdf.add_page()
pdf.set_font('Helvetica', 'B', 18)
pdf.cell(0, 10, 'Detailed Test Results', 0, 1)

for r in data['results']:
    # Check if we need a new page
    if pdf.get_y() > 220:
        pdf.add_page()
    
    pdf.ln(3)
    pdf.set_font('Helvetica', 'B', 12)
    pdf.set_fill_color(240, 240, 240)
    pdf.cell(0, 8, f'Test #{r["test_id"]}: {r["profile"]} - Grade {r["grade"]}', 0, 1, 'L', True)
    
    pdf.set_font('Helvetica', '', 10)
    pdf.cell(0, 5, f'Target Muscles: {", ".join(r["target_muscles"])}', 0, 1)
    pdf.cell(0, 5, f'Equipment: {", ".join(r["equipment"])}', 0, 1)
    pdf.cell(0, 5, f'Pool Size: {r["matching_pool"]} exercises | Selected: {r["workout_count"]}', 0, 1)
    
    pdf.ln(2)
    pdf.set_font('Helvetica', 'B', 10)
    pdf.cell(0, 5, 'Exercises Returned:', 0, 1)
    pdf.set_font('Helvetica', '', 9)
    
    for i, ex in enumerate(r['workout_exercises'], 1):
        muscles = ex['muscles'] if ex['muscles'] else ['N/A']
        if isinstance(muscles, list):
            muscles = ', '.join(str(m) for m in muscles)
        equip = ex['equipment'] if ex['equipment'] else 'Bodyweight'
        pdf.cell(0, 4, f'  {i}. {ex["name"][:50]}', 0, 1)
        pdf.cell(0, 4, f'      Equipment: {equip} | Muscles: {muscles}', 0, 1)
    
    pdf.ln(2)
    pdf.set_font('Helvetica', 'B', 10)
    pdf.cell(0, 5, 'Scores:', 0, 1)
    pdf.set_font('Helvetica', '', 9)
    pdf.cell(0, 4, f'  Equipment: {r["scores"]["equipment_accuracy"]}% | Muscle: {r["scores"]["muscle_accuracy"]}% | Variety: {r["scores"]["variety"]}% | Quality: {r["scores"]["quality"]}%', 0, 1)
    pdf.set_font('Helvetica', 'B', 10)
    pdf.cell(0, 5, f'  Overall: {r["scores"]["overall"]}%', 0, 1)
    
    if r['issues']:
        pdf.set_font('Helvetica', 'I', 9)
        pdf.set_text_color(150, 100, 0)
        for issue in r['issues'][:2]:
            issue_clean = issue.replace('\u26a0\ufe0f', '!').replace('\u2705', '+')
            pdf.cell(0, 4, f'  {issue_clean[:70]}', 0, 1)
        pdf.set_text_color(0, 0, 0)
    
    pdf.ln(2)

# Save PDF
output_path = '/Users/josephreed/Desktop/Workout App/AutoGen_Test_Report.pdf'
pdf.output(output_path)
print(f'PDF saved to: {output_path}')

