//
//  ProgramAuditView.swift
//  GoFit
//
//  View for running and displaying the program generation audit
//
//  ⚠️ DEBUG ONLY - This entire file is excluded from production builds

#if DEBUG

import SwiftUI

struct ProgramAuditView: View {
    @StateObject private var auditor = ProgramGenerationAuditor.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDetailedResults = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                if auditor.isRunning {
                    progressSection
                } else if let summary = auditor.summary {
                    summarySection(summary)
                    topIssuesSection(summary)
                    scoreBreakdownSection
                    if showDetailedResults {
                        detailedResultsSection
                    }
                } else {
                    startSection
                }
            }
            .padding()
        }
        .background(colorScheme == .dark ? Color.black : Color(.systemGroupedBackground))
        .navigationTitle("Program Audit")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("Program Generation Audit")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Tests 100 diverse user profiles against the program generation logic")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Start Section
    
    private var startSection: some View {
        VStack(spacing: 16) {
            Text("This audit will:")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                auditFeatureRow(icon: "person.3.fill", text: "Create 100 diverse test user profiles")
                auditFeatureRow(icon: "dumbbell.fill", text: "Generate workouts for each user")
                auditFeatureRow(icon: "checkmark.circle.fill", text: "Grade exercise selection quality")
                auditFeatureRow(icon: "chart.bar.fill", text: "Score equipment utilization")
                auditFeatureRow(icon: "target", text: "Verify goal alignment")
                auditFeatureRow(icon: "exclamationmark.triangle.fill", text: "Identify issues and improvements")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
            )
            
            Button(action: {
                Task {
                    await auditor.runAudit()
                }
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Run Audit")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(12)
            }
        }
        .padding()
    }
    
    private func auditFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 16) {
            ProgressView(value: auditor.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
            
            Text(auditor.currentStatus)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("\(Int(auditor.progress * 100))%")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.green)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
        )
    }
    
    // MARK: - Summary Section
    
    private func summarySection(_ summary: AuditSummary) -> some View {
        VStack(spacing: 16) {
            // Main Score
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: summary.averageScore / 100)
                    .stroke(
                        scoreGradient(for: summary.averageScore),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", summary.averageScore))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(scoreColor(for: summary.averageScore))
                    
                    Text("/ 100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(scoreLabel(for: summary.averageScore))
                .font(.headline)
                .foregroundColor(scoreColor(for: summary.averageScore))
            
            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(title: "Users Tested", value: "\(summary.totalUsers)", icon: "person.3.fill")
                statCard(title: "Pass Rate", value: String(format: "%.0f%%", summary.passRate), icon: "checkmark.circle.fill")
                statCard(title: "Total Workouts", value: "\(summary.totalWorkouts)", icon: "dumbbell.fill")
                statCard(title: "Issues Found", value: "\(summary.topIssues.reduce(0) { $0 + $1.count })", icon: "exclamationmark.triangle.fill")
            }
            
            // Equipment Utilization
            VStack(alignment: .leading, spacing: 8) {
                Text("Equipment Utilization")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Gym Users")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f/100", summary.equipmentUtilizationByLocation["Gym"] ?? 0))
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Home Users")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f/100", summary.equipmentUtilizationByLocation["Home"] ?? 0))
                            .font(.headline)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : Color(.systemGray6))
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
        )
    }
    
    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.green)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.1) : Color(.systemGray6))
        )
    }
    
    // MARK: - Top Issues Section
    
    private func topIssuesSection(_ summary: AuditSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Issues Found")
                .font(.headline)
            
            ForEach(Array(summary.topIssues.prefix(5).enumerated()), id: \.offset) { index, issue in
                HStack {
                    Circle()
                        .fill(issueColor(for: index))
                        .frame(width: 8, height: 8)
                    
                    Text(issue.issue)
                        .font(.subheadline)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    Text("\(issue.count)x")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
            
            if summary.topIssues.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No major issues found!")
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
        )
    }
    
    // MARK: - Score Breakdown Section
    
    private var scoreBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Score Breakdown")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showDetailedResults.toggle() }) {
                    Text(showDetailedResults ? "Hide Details" : "Show Details")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                scoreRow(label: "90-100", description: "Excellent - Optimal generation", color: .green)
                scoreRow(label: "70-89", description: "Good - Minor improvements needed", color: .yellow)
                scoreRow(label: "50-69", description: "Fair - Significant issues", color: .orange)
                scoreRow(label: "Below 50", description: "Poor - Major fixes required", color: .red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
        )
    }
    
    private func scoreRow(label: String, description: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .leading)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    // MARK: - Detailed Results Section
    
    private var detailedResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 10 Results")
                .font(.headline)
            
            ForEach(Array(auditor.results.sorted { $0.overallScore > $1.overallScore }.prefix(10).enumerated()), id: \.offset) { index, result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        Text(result.userName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text(String(format: "%.0f", result.overallScore))
                            .font(.headline)
                            .foregroundColor(scoreColor(for: result.overallScore))
                    }
                    
                    Text("\(result.userProfile.experienceLevel) | \(result.userProfile.fitnessGoal) | \(result.userProfile.workoutLocation)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !result.issues.isEmpty {
                        Text("Issues: \(result.issues.first ?? "")")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
                
                if index < 9 {
                    Divider()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
        )
    }
    
    // MARK: - Helpers
    
    private func scoreColor(for score: Double) -> Color {
        if score >= 90 { return .green }
        if score >= 70 { return .yellow }
        if score >= 50 { return .orange }
        return .red
    }
    
    private func scoreGradient(for score: Double) -> LinearGradient {
        if score >= 90 { return LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing) }
        if score >= 70 { return LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing) }
        if score >= 50 { return LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing) }
        return LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
    }
    
    private func scoreLabel(for score: Double) -> String {
        if score >= 90 { return "Excellent" }
        if score >= 70 { return "Good" }
        if score >= 50 { return "Fair" }
        return "Needs Improvement"
    }
    
    private func issueColor(for index: Int) -> Color {
        if index < 2 { return .red }
        if index < 4 { return .orange }
        return .yellow
    }
}

#Preview {
    NavigationStack {
        ProgramAuditView()
    }
}

#endif // DEBUG
