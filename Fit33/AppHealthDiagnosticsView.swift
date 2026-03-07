// AppHealthDiagnosticsView.swift
// Fit33
//
// UI for the App Health Diagnostic System
// Shows detailed health report with all checks, auto-fixes, and recommendations.
//

import SwiftUI

struct AppHealthDiagnosticsView: View {
    @StateObject private var diagnostics = AppHealthDiagnostics.shared
    @State private var report: DiagnosticReport?
    @State private var isRunning = false
    @State private var selectedFilter: DiagnosticFilter = .all
    
    enum DiagnosticFilter: String, CaseIterable {
        case all = "All"
        case critical = "Critical"
        case warnings = "Warnings"
        case autoFixed = "Auto-Fixed"
        case passed = "Passed"
    }
    
    var filteredResults: [DiagnosticResult] {
        guard let report = report else { return [] }
        switch selectedFilter {
        case .all: return report.results
        case .critical: return report.results.filter { $0.severity == .critical }
        case .warnings: return report.results.filter { $0.severity == .warning }
        case .autoFixed: return report.results.filter { $0.autoFixed }
        case .passed: return report.results.filter { $0.severity == .passed }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Run Button
                runButton
                
                if isRunning {
                    progressSection
                }
                
                if let report = report {
                    // Score Card
                    scoreCard(report)
                    
                    // Summary Stats
                    summaryStats(report)
                    
                    // Filter Tabs
                    filterTabs
                    
                    // Results List
                    resultsSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("App Health")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("App Health Diagnostics")
                .font(.title2.bold())
            
            Text("Deep scan of all app subsystems")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 10)
    }
    
    // MARK: - Run Button
    
    private var runButton: some View {
        Button {
            Task {
                isRunning = true
                report = await diagnostics.runFullDiagnostic()
                isRunning = false
            }
        } label: {
            HStack {
                Image(systemName: isRunning ? "arrow.triangle.2.circlepath" : "play.fill")
                    .rotationEffect(.degrees(isRunning ? 360 : 0))
                    .animation(isRunning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRunning)
                Text(isRunning ? "Running Diagnostics..." : "Run Full Diagnostic")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isRunning)
    }
    
    // MARK: - Progress
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: diagnostics.progress)
                .tint(.blue)
            
            Text("Checking: \(diagnostics.currentCheck)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }
    
    // MARK: - Score Card
    
    private func scoreCard(_ report: DiagnosticReport) -> some View {
        VStack(spacing: 12) {
            // Score Circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: CGFloat(report.healthScore) / 100)
                    .stroke(
                        scoreColor(report.healthScore),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(report.healthScore)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("/ 100")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(report.overallHealth)
                .font(.headline)
            
            Text("Completed in \(String(format: "%.2f", report.duration))s")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
    }
    
    // MARK: - Summary Stats
    
    private func summaryStats(_ report: DiagnosticReport) -> some View {
        HStack(spacing: 12) {
            statBadge(count: report.criticalCount, label: "Critical", color: .red, icon: "exclamationmark.circle.fill")
            statBadge(count: report.warningCount, label: "Warnings", color: .orange, icon: "exclamationmark.triangle.fill")
            statBadge(count: report.autoFixedCount, label: "Fixed", color: .green, icon: "wrench.and.screwdriver.fill")
            statBadge(count: report.passedCount, label: "Passed", color: .blue, icon: "checkmark.circle.fill")
        }
    }
    
    private func statBadge(count: Int, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text("\(count)")
                .font(.title2.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }
    
    // MARK: - Filter Tabs
    
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiagnosticFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedFilter == filter ? Color.blue : Color(.tertiarySystemGroupedBackground))
                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
    
    // MARK: - Results
    
    private var resultsSection: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredResults) { result in
                resultRow(result)
            }
        }
    }
    
    private func resultRow(_ result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.severity.rawValue)
                    .font(.caption.bold())
                
                Spacer()
                
                Text(result.category)
                    .font(.caption2)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                
                if result.autoFixed {
                    Text("AUTO-FIXED")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
            }
            
            Text(result.check)
                .font(.subheadline.bold())
            
            Text(result.message)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let fix = result.fix {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.fill")
                        .font(.caption2)
                    Text(fix)
                        .font(.caption2)
                }
                .foregroundColor(.orange)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }
    
    // MARK: - Helpers
    
    private func scoreColor(_ score: Int) -> LinearGradient {
        if score >= 80 {
            return LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
        } else if score >= 50 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
        }
    }
}
