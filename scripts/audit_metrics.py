#!/usr/bin/env python3
"""
Fit33 Codebase Audit Metrics — Before/After Comparison Tool
Captures quantitative code health metrics for tracking improvement.
Run: python3 scripts/audit_metrics.py [--label before|after]
"""

import os, re, glob, json, sys
from datetime import datetime
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIT33 = os.path.join(ROOT, 'Fit33')
SUPABASE = os.path.join(ROOT, 'supabase')

def count_pattern(directory, extension, pattern):
    """Count regex pattern matches across files with given extension."""
    total = 0
    pat = re.compile(pattern)
    for dp, _, fs in os.walk(directory):
        for f in fs:
            if f.endswith(extension):
                try:
                    with open(os.path.join(dp, f), 'r', encoding='utf-8', errors='ignore') as fh:
                        total += len(pat.findall(fh.read()))
                except Exception:
                    pass
    return total

def file_line_counts(directory, extension):
    """Return dict of {filepath: line_count} for all files with extension."""
    counts = {}
    for dp, _, fs in os.walk(directory):
        for f in fs:
            if f.endswith(extension):
                p = os.path.join(dp, f)
                try:
                    with open(p, 'r', encoding='utf-8', errors='ignore') as fh:
                        counts[p] = sum(1 for _ in fh)
                except Exception:
                    pass
    return counts

def count_files(directory, extension):
    """Count files with given extension."""
    return len(file_line_counts(directory, extension))

def sql_function_duplicates(directory):
    """Find SQL function names defined in multiple files."""
    pat = re.compile(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([a-zA-Z0-9_\.]+)\s*\(', re.I)
    where = defaultdict(set)
    for dp, _, fs in os.walk(directory):
        for f in fs:
            if f.endswith('.sql'):
                p = os.path.join(dp, f)
                try:
                    txt = open(p, 'r', encoding='utf-8', errors='ignore').read()
                    for m in pat.finditer(txt):
                        where[m.group(1).lower()].add(p)
                except Exception:
                    pass
    total_funcs = len(where)
    duplicates = sum(1 for v in where.values() if len(v) > 1)
    return total_funcs, duplicates

def count_hardcoded_secrets(directory):
    """Count likely hardcoded API keys/secrets in Swift files."""
    patterns = [
        r'(?:apiKey|clientSecret|client_secret|authToken|api_key)\s*[:=]\s*"[A-Za-z0-9_\-]{10,}"',
        r'"eyJ[A-Za-z0-9_\-]{20,}"',  # JWT tokens
    ]
    total = 0
    for pat_str in patterns:
        total += count_pattern(directory, '.swift', pat_str)
    return total

def count_todos_in_code(directory):
    """Count TODO/FIXME in Swift and TypeScript files."""
    total = 0
    for ext in ['.swift', '.ts']:
        total += count_pattern(directory, ext, r'\bTODO\b|\bFIXME\b')
    return total

def gather_metrics():
    """Gather all audit metrics."""
    swift_sizes = file_line_counts(FIT33, '.swift')
    sql_sizes = file_line_counts(SUPABASE, '.sql')
    
    sorted_swift = sorted(swift_sizes.items(), key=lambda x: x[1], reverse=True)
    top5_large = [(os.path.basename(p), n) for p, n in sorted_swift[:5]]
    files_over_1000 = sum(1 for _, n in swift_sizes.items() if n > 1000)
    files_over_3000 = sum(1 for _, n in swift_sizes.items() if n > 3000)
    
    total_funcs, dup_funcs = sql_function_duplicates(SUPABASE)
    
    metrics = {
        'timestamp': datetime.now().isoformat(),
        
        # File counts
        'swift_files': len(swift_sizes),
        'sql_files': len(sql_sizes),
        'total_swift_lines': sum(swift_sizes.values()),
        
        # Size metrics
        'largest_swift_file_lines': sorted_swift[0][1] if sorted_swift else 0,
        'largest_swift_file_name': os.path.basename(sorted_swift[0][0]) if sorted_swift else '',
        'top5_largest_files': top5_large,
        'files_over_1000_lines': files_over_1000,
        'files_over_3000_lines': files_over_3000,
        
        # Code smell metrics
        'print_call_sites': count_pattern(FIT33, '.swift', r'print\("'),
        'navigation_view_count': count_pattern(FIT33, '.swift', r'\bNavigationView\s*\{'),
        'navigation_stack_count': count_pattern(FIT33, '.swift', r'\bNavigationStack\s*\{'),
        'async_trigger_points': count_pattern(FIT33, '.swift', r'\.task\s*\{|\.onAppear\s*\{|Task\.detached|DispatchQueue\.main\.asyncAfter'),
        'force_unwrap_count': count_pattern(FIT33, '.swift', r'\bas!\b|try!'),
        'fatal_error_count': count_pattern(FIT33, '.swift', r'fatalError\('),
        
        # Security metrics
        'hardcoded_secrets_swift': count_hardcoded_secrets(FIT33),
        'todo_fixme_count': count_todos_in_code(ROOT),
        
        # SQL health
        'sql_functions_defined': total_funcs,
        'sql_duplicate_definitions': dup_funcs,
        
        # Test coverage indicator
        'test_files': count_pattern(FIT33, '.swift', r'(?:XCTestCase|func test[A-Z])'),
        
        # Design system
        'inline_color_definitions': count_pattern(FIT33, '.swift', r'Color\(red:\s*\d'),
        'inline_font_definitions': count_pattern(FIT33, '.swift', r'\.font\(\.system\(size:'),
    }
    
    return metrics

def print_metrics(metrics, label=''):
    """Pretty-print metrics."""
    print(f"\n{'='*60}")
    print(f"  FIT33 CODEBASE AUDIT METRICS — {label.upper()}")
    print(f"  Captured: {metrics['timestamp']}")
    print(f"{'='*60}\n")
    
    sections = [
        ("FILE STRUCTURE", [
            ('Swift files', 'swift_files'),
            ('SQL files', 'sql_files'),
            ('Total Swift lines', 'total_swift_lines'),
            ('Files over 1000 lines', 'files_over_1000_lines'),
            ('Files over 3000 lines', 'files_over_3000_lines'),
            ('Largest file', 'largest_swift_file_name'),
            ('Largest file lines', 'largest_swift_file_lines'),
        ]),
        ("CODE QUALITY", [
            ('print() call sites', 'print_call_sites'),
            ('NavigationView usages', 'navigation_view_count'),
            ('NavigationStack usages', 'navigation_stack_count'),
            ('Async trigger points', 'async_trigger_points'),
            ('Force unwraps (as!/try!)', 'force_unwrap_count'),
            ('fatalError() calls', 'fatal_error_count'),
            ('TODO/FIXME markers', 'todo_fixme_count'),
        ]),
        ("SECURITY", [
            ('Hardcoded secrets (Swift)', 'hardcoded_secrets_swift'),
        ]),
        ("BACKEND SQL", [
            ('SQL functions defined', 'sql_functions_defined'),
            ('Duplicate SQL definitions', 'sql_duplicate_definitions'),
        ]),
        ("DESIGN CONSISTENCY", [
            ('Inline Color(red:) defs', 'inline_color_definitions'),
            ('Inline .font(.system) defs', 'inline_font_definitions'),
        ]),
    ]
    
    for title, items in sections:
        print(f"  [{title}]")
        for label_str, key in items:
            val = metrics.get(key, 'N/A')
            print(f"    {label_str:35s} {val}")
        print()
    
    print("  [TOP 5 LARGEST FILES]")
    for name, lines in metrics.get('top5_largest_files', []):
        print(f"    {name:45s} {lines:,} lines")
    print()

def compare_metrics(before, after):
    """Print before/after comparison."""
    print(f"\n{'='*70}")
    print(f"  FIT33 AUDIT METRICS — BEFORE vs AFTER COMPARISON")
    print(f"{'='*70}\n")
    
    compare_keys = [
        ('print() call sites', 'print_call_sites', 'lower'),
        ('NavigationView usages', 'navigation_view_count', 'lower'),
        ('NavigationStack usages', 'navigation_stack_count', 'higher'),
        ('Files over 3000 lines', 'files_over_3000_lines', 'lower'),
        ('Files over 1000 lines', 'files_over_1000_lines', 'lower'),
        ('Largest file lines', 'largest_swift_file_lines', 'lower'),
        ('Async trigger points', 'async_trigger_points', 'lower'),
        ('Hardcoded secrets', 'hardcoded_secrets_swift', 'lower'),
        ('TODO/FIXME markers', 'todo_fixme_count', 'lower'),
        ('SQL duplicate defs', 'sql_duplicate_definitions', 'lower'),
        ('Inline Color defs', 'inline_color_definitions', 'lower'),
        ('Force unwraps', 'force_unwrap_count', 'lower'),
        ('fatalError calls', 'fatal_error_count', 'lower'),
    ]
    
    print(f"  {'Metric':40s} {'Before':>8s} {'After':>8s} {'Delta':>8s} {'Status':>10s}")
    print(f"  {'-'*40} {'-'*8} {'-'*8} {'-'*8} {'-'*10}")
    
    for label_str, key, direction in compare_keys:
        b = before.get(key, 0)
        a = after.get(key, 0)
        delta = a - b
        if delta == 0:
            status = '—'
        elif (direction == 'lower' and delta < 0) or (direction == 'higher' and delta > 0):
            status = '✅ Better'
        else:
            status = '⚠️ Worse'
        
        delta_str = f"{delta:+d}" if isinstance(delta, int) else f"{delta:+.0f}"
        print(f"  {label_str:40s} {b:>8} {a:>8} {delta_str:>8s} {status:>10s}")
    
    print()

if __name__ == '__main__':
    label = 'snapshot'
    if len(sys.argv) > 1 and sys.argv[1] in ('--label', '-l'):
        label = sys.argv[2] if len(sys.argv) > 2 else 'snapshot'
    elif len(sys.argv) > 1:
        label = sys.argv[1]
    
    metrics = gather_metrics()
    print_metrics(metrics, label)
    
    # Save to JSON
    output_file = os.path.join(ROOT, f'audit_metrics_{label}.json')
    with open(output_file, 'w') as f:
        json.dump(metrics, f, indent=2)
    print(f"  Saved to: {output_file}")
    
    # If both before and after exist, show comparison
    before_file = os.path.join(ROOT, 'audit_metrics_before.json')
    after_file = os.path.join(ROOT, 'audit_metrics_after.json')
    if label == 'after' and os.path.exists(before_file):
        with open(before_file) as f:
            before = json.load(f)
        compare_metrics(before, metrics)
