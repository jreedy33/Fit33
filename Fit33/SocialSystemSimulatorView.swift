//
//  SocialSystemSimulatorView.swift
//  Fit33
//
//  UI for running the Social System Simulator from the Dev Menu.
//  Provides live log output, progress tracking, and report viewing.
//
//  Created by Infrastructure Team - 2026-02-25
//

import SwiftUI

#if DEBUG

// MARK: - Main Simulator View

struct SocialSystemSimulatorView: View {
    @StateObject private var simulator = SocialSystemSimulator.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var userAName = "Me"  // Always uses the currently logged-in user
    @State private var userBName = ""    // Searches for a real user by name/username
    @State private var userCName = ""    // Third user for group challenge tests
    @State private var includeGroupChallenges = true
    @State private var selectedChallengeTypes: Set<ChallengeType> = Set(ChallengeType.allCases)
    @State private var showReport = false
    @State private var showFilters = false
    @State private var realtimeTestResult: QuickRealtimeTestResult?
    @State private var showRealtimeResult = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(white: 0.06), Color.black]
                    : [Color(red: 0.95, green: 0.96, blue: 0.98), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Configuration Card
                        if !simulator.isRunning {
                            configurationCard
                        }
                        
                        // Status Card
                        if simulator.isRunning || simulator.report != nil {
                            statusCard
                        }
                        
                        // Live Log
                        if !simulator.liveLog.isEmpty {
                            liveLogCard
                        }
                        
                        // Report Summary
                        if let report = simulator.report, !simulator.isRunning {
                            reportSummaryCard(report)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showReport) {
            if let report = simulator.report {
                SimulationReportDetailView(report: report)
            }
        }
        .sheet(isPresented: $showRealtimeResult) {
            QuickRealtimeTestResultView(result: realtimeTestResult)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("🧪 Social System Simulator")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Test friends, challenges & realtime")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            if simulator.isRunning {
                ProgressView()
                    .tint(.blue)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Configuration Card
    
    private var configurationCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("Test Users")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("User A (You)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.green)
                        Text("Logged-in user")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(CornerRadius.sm)
                }
                
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("User B (Opponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Search name or username...", text: $userBName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Text("User A is always you. User B & C are found by searching your database — leave blank to auto-pick.")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // User C for group challenges
            VStack(alignment: .leading, spacing: 4) {
                Text("User C (Group Challenges)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Third user name/username (optional)...", text: $userCName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Challenge type filter
            DisclosureGroup("Challenge Types (\(selectedChallengeTypes.count)/\(ChallengeType.allCases.count))", isExpanded: $showFilters) {
                VStack(spacing: 8) {
                    ForEach(ChallengeType.allCases) { type in
                        HStack {
                            Text(type.emoji)
                            Text(type.displayName)
                                .font(.subheadline)
                            Spacer()
                            
                            Image(systemName: selectedChallengeTypes.contains(type) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedChallengeTypes.contains(type) ? .green : .gray)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedChallengeTypes.contains(type) {
                                selectedChallengeTypes.remove(type)
                            } else {
                                selectedChallengeTypes.insert(type)
                            }
                        }
                    }
                    
                    Toggle("Include Group Challenges", isOn: $includeGroupChallenges)
                        .font(.subheadline)
                }
                .padding(.top, 8)
            }
            
            // Run button
            Button {
                Task {
                    await simulator.runFullSimulation(
                        userAName: userAName,
                        userBName: userBName,
                        userCName: userCName,
                        challengeTypes: selectedChallengeTypes.count == ChallengeType.allCases.count ? nil : Array(selectedChallengeTypes),
                        includeGroupChallenges: includeGroupChallenges
                    )
                }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Run Full Simulation")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(CornerRadius.md)
            }
            .disabled(simulator.isRunning)
            
            // Quick Realtime Test — one-tap test to verify WebSocket updates work
            Button {
                Task {
                    realtimeTestResult = nil
                    showRealtimeResult = true
                    realtimeTestResult = await simulator.quickRealtimeTest(userBName: userBName)
                }
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("⚡ Quick Realtime Test")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(CornerRadius.md)
            }
            .disabled(simulator.isRunning)
            
            // Nuke button — cancels all active challenges, pending requests, etc.
            Button {
                Task { await simulator.nukeAllTestData() }
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Cancel All Active Challenges & Requests")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(Color.red.opacity(0.15))
                .foregroundColor(.red)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(simulator.isRunning)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : .white)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(simulator.currentPhase)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(simulator.progress * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: simulator.progress)
                .tint(.blue)
            
            Text(simulator.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color.cardBackground : .white)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }
    
    // MARK: - Live Log Card
    
    private var liveLogCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundColor(.orange)
                Text("Live Log")
                    .font(.headline)
                Spacer()
                Text("\(simulator.liveLog.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(simulator.liveLog.suffix(50).reversed()) { entry in
                        logEntryRow(entry)
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : .white)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }
    
    private func logEntryRow(_ entry: SimulationLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Severity icon
            Text(severityIcon(entry.severity))
                .font(.caption2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.action)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(entry.success ? .primary : .red)
                
                if let details = entry.details {
                    Text(details)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Text("\(entry.durationMs)ms")
                .font(.caption2)
                .foregroundColor(entry.durationMs > 3000 ? .red : (entry.durationMs > 1000 ? .orange : .secondary))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(entry.success ? Color.clear : Color.red.opacity(0.08))
        )
    }
    
    private func severityIcon(_ severity: String) -> String {
        switch severity {
        case "PASS": return "✅"
        case "FAIL": return "❌"
        case "ERROR": return "🚨"
        case "WARN": return "⚠️"
        default: return "ℹ️"
        }
    }
    
    // MARK: - Report Summary Card
    
    private func reportSummaryCard(_ report: SimulationReport) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                Text("Simulation Report")
                    .font(.headline)
                Spacer()
                
                Button("Full Report") {
                    showReport = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            // Stats Grid
            HStack(spacing: 16) {
                statBox(value: "\(report.totalTests)", label: "Total", color: .blue)
                statBox(value: "\(report.passedTests)", label: "Passed", color: .green)
                statBox(value: "\(report.failedTests)", label: "Failed", color: .red)
                statBox(value: "\(report.warnings)", label: "Warnings", color: .orange)
            }
            
            // Pass Rate
            HStack {
                Text("Pass Rate")
                    .font(.subheadline)
                Spacer()
                Text("\(String(format: "%.1f", report.passRate))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(report.passRate >= 90 ? .green : (report.passRate >= 70 ? .orange : .red))
            }
            
            // Duration
            if let completedAt = report.completedAt {
                HStack {
                    Text("Duration")
                        .font(.subheadline)
                    Spacer()
                    Text("\(String(format: "%.1f", completedAt.timeIntervalSince(report.startedAt)))s")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Issues
            if !report.issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issues Found (\(report.issues.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(report.issues.prefix(5)) { issue in
                        HStack(alignment: .top, spacing: 6) {
                            Text(issue.severity == "CRITICAL" ? "🚨" : (issue.severity == "HIGH" ? "🔴" : "🟡"))
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(issue.category)] \(issue.description)")
                                    .font(.caption)
                                if let fix = issue.suggestedFix {
                                    Text("Fix: \(fix)")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            
            // Recommendations
            if !report.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommendations")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(report.recommendations, id: \.self) { rec in
                        Text(rec)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : .white)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }
    
    private func statBox(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Detailed Report View

struct SimulationReportDetailView: View {
    let report: SimulationReport
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var filterPhase: String = "ALL"
    @State private var filterSeverity: String = "ALL"
    @State private var showOnlyFailed = false
    
    private var filteredLogs: [SimulationLogEntry] {
        report.logs.filter { entry in
            if showOnlyFailed && entry.success { return false }
            if filterPhase != "ALL" && entry.phase != filterPhase { return false }
            if filterSeverity != "ALL" && entry.severity != filterSeverity { return false }
            return true
        }
    }
    
    private var allPhases: [String] {
        ["ALL"] + Array(Set(report.logs.map(\.phase))).sorted()
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Summary Section
                Section("Summary") {
                    LabeledContent("Simulation ID", value: report.simulationId)
                    LabeledContent("User A", value: "\(report.userA.name) (\(report.userA.userId.uuidString.prefix(8)))")
                    LabeledContent("User B", value: "\(report.userB.name) (\(report.userB.userId.uuidString.prefix(8)))")
                    LabeledContent("Total Tests", value: "\(report.totalTests)")
                    LabeledContent("Passed", value: "\(report.passedTests)")
                    LabeledContent("Failed", value: "\(report.failedTests)")
                    LabeledContent("Pass Rate", value: "\(String(format: "%.1f", report.passRate))%")
                    if let completedAt = report.completedAt {
                        LabeledContent("Duration", value: "\(String(format: "%.1f", completedAt.timeIntervalSince(report.startedAt)))s")
                    }
                }
                
                // Issues Section
                if !report.issues.isEmpty {
                    Section("Issues (\(report.issues.count))") {
                        ForEach(report.issues) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(issue.severity)
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(issueSeverityColor(issue.severity).opacity(0.2))
                                        .cornerRadius(4)
                                    Text(issue.category)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(issue.description)
                                    .font(.subheadline)
                                if let fix = issue.suggestedFix {
                                    Text("💡 \(fix)")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Recommendations Section
                if !report.recommendations.isEmpty {
                    Section("Recommendations") {
                        ForEach(report.recommendations, id: \.self) { rec in
                            Text(rec)
                                .font(.subheadline)
                        }
                    }
                }
                
                // Filters
                Section("Log Filters") {
                    Picker("Phase", selection: $filterPhase) {
                        ForEach(allPhases, id: \.self) { phase in
                            Text(phase).tag(phase)
                        }
                    }
                    
                    Picker("Severity", selection: $filterSeverity) {
                        ForEach(["ALL", "PASS", "FAIL", "ERROR", "WARN", "INFO"], id: \.self) { sev in
                            Text(sev).tag(sev)
                        }
                    }
                    
                    Toggle("Show Only Failed", isOn: $showOnlyFailed)
                }
                
                // Detailed Logs
                Section("Detailed Logs (\(filteredLogs.count))") {
                    ForEach(filteredLogs) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.success ? "✅" : "❌")
                                    .font(.caption2)
                                Text(entry.phase)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(3)
                                Spacer()
                                Text("\(entry.durationMs)ms")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundColor(entry.durationMs > 3000 ? .red : .secondary)
                            }
                            
                            Text(entry.action)
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            if let details = entry.details {
                                Text(details)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text(entry.service)
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                                Text("→")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(entry.rpcOrMethod)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Simulation Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    ShareLink(
                        item: reportAsText(),
                        subject: Text("Fit33 Social Simulation Report"),
                        message: Text("Social System Simulator Report - \(report.simulationId)")
                    )
                }
            }
        }
    }
    
    private func issueSeverityColor(_ severity: String) -> Color {
        switch severity {
        case "CRITICAL": return .red
        case "HIGH": return .orange
        case "MEDIUM": return .yellow
        case "LOW": return .blue
        default: return .gray
        }
    }
    
    private func reportAsText() -> String {
        var text = """
        ═══════════════════════════════════════════════════════════
        FIT33 SOCIAL SYSTEM SIMULATION REPORT
        ═══════════════════════════════════════════════════════════
        ID: \(report.simulationId)
        Date: \(report.startedAt)
        User A: \(report.userA.name) (\(report.userA.userId))
        User B: \(report.userB.name) (\(report.userB.userId))
        
        RESULTS:
          Total Tests: \(report.totalTests)
          Passed: \(report.passedTests)
          Failed: \(report.failedTests)
          Warnings: \(report.warnings)
          Pass Rate: \(String(format: "%.1f", report.passRate))%
        
        """
        
        if !report.issues.isEmpty {
            text += "ISSUES:\n"
            for issue in report.issues {
                text += "  [\(issue.severity)] \(issue.category): \(issue.description)\n"
                if let fix = issue.suggestedFix {
                    text += "    Fix: \(fix)\n"
                }
            }
            text += "\n"
        }
        
        if !report.recommendations.isEmpty {
            text += "RECOMMENDATIONS:\n"
            for rec in report.recommendations {
                text += "  → \(rec)\n"
            }
            text += "\n"
        }
        
        text += "DETAILED LOG:\n"
        text += "───────────────────────────────────────────────────────────\n"
        for entry in report.logs {
            text += "[\(entry.severity)] [\(entry.phase)] \(entry.action) (\(entry.durationMs)ms)"
            if let details = entry.details {
                text += " | \(details)"
            }
            text += "\n"
        }
        
        return text
    }
}

// MARK: - Quick Realtime Test Result View

struct QuickRealtimeTestResultView: View {
    let result: QuickRealtimeTestResult?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let result = result {
                    // Header with big status indicator
                    VStack(spacing: 12) {
                        Text(result.passed ? "⚡️" : "🔌")
                            .font(.system(size: 60))
                        
                        Text(result.summary)
                            .font(.title3)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(result.passed ? .green : .red)
                        
                        if result.latencyMs > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text("Latency: \(result.latencyMs)ms")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(result.latencyMs < 1000 ? .green : (result.latencyMs < 3000 ? .orange : .red))
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(result.latencyMs < 1000 ? Color.green.opacity(0.15) : (result.latencyMs < 3000 ? Color.orange.opacity(0.15) : Color.red.opacity(0.15)))
                            )
                        }
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .background(
                        result.passed
                            ? Color.green.opacity(0.08)
                            : Color.red.opacity(0.08)
                    )
                    
                    // Detail log
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(result.details.enumerated()), id: \.offset) { _, line in
                                if line.isEmpty {
                                    Divider()
                                        .padding(.vertical, 4)
                                } else {
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(
                                            line.hasPrefix("✅") ? .green :
                                            line.hasPrefix("❌") ? .red :
                                            line.hasPrefix("⚠️") ? .orange :
                                            line.hasPrefix("⚡️") ? .blue :
                                            line.hasPrefix("⏳") ? .secondary :
                                            .primary
                                        )
                                }
                            }
                        }
                        .padding()
                    }
                    .background(colorScheme == .dark ? Color(white: 0.06) : Color(white: 0.97))
                } else {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("⚡️ Testing Realtime...")
                            .font(.headline)
                        Text("Logging opponent progress and waiting for WebSocket event...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Quick Realtime Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                
                if let result = result {
                    ToolbarItem(placement: .navigationBarLeading) {
                        ShareLink(
                            item: result.details.joined(separator: "\n"),
                            subject: Text("Realtime Test Result"),
                            message: Text(result.summary)
                        )
                    }
                }
            }
        }
    }
}

#endif
