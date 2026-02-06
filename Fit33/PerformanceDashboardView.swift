import SwiftUI
import Charts

// MARK: - Performance Dashboard View
/// Developer tool to review performance metrics collected during navigation
/// Shows real-time and historical performance data

struct PerformanceDashboardView: View {
    @StateObject private var monitor = PerformanceMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Animated blue/cyan orb background
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Status Banner
                        statusBanner
                        
                        // Tabs
                        Picker("", selection: $selectedTab) {
                            Text("Overview").tag(0)
                            Text("Views").tag(1)
                            Text("Issues").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        // Content based on selected tab
                        switch selectedTab {
                        case 0:
                            overviewTab
                        case 1:
                            viewsTab
                        case 2:
                            issuesTab
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.top)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Performance Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if monitor.isMonitoring {
                            monitor.stopMonitoring()
                        } else {
                            monitor.startMonitoring()
                        }
                    }) {
                        Image(systemName: monitor.isMonitoring ? "pause.fill" : "play.fill")
                            .foregroundColor(monitor.isMonitoring ? .red : .green)
                    }
                }
            }
        }
    }
    
    // MARK: - Status Banner
    
    private var statusBanner: some View {
        HStack(spacing: 15) {
            // Monitoring Status
            VStack(spacing: 4) {
                Text(monitor.isMonitoring ? "MONITORING" : "PAUSED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(monitor.isMonitoring ? .green : .orange)
                
                Circle()
                    .fill(monitor.isMonitoring ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
            
            Divider()
                .frame(height: 30)
            
            // Quick Stats
            quickStat(title: "FPS", value: String(format: "%.0f", monitor.currentFPS), color: fpsColor)
            quickStat(title: "Memory", value: String(format: "%.0f", monitor.currentMemoryMB) + "MB", color: memoryColor)
            quickStat(title: "CPU", value: String(format: "%.0f", monitor.currentCPUPercent) + "%", color: cpuColor)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func quickStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Colors
    
    private var fpsColor: Color {
        if monitor.currentFPS >= 55 { return .green }
        if monitor.currentFPS >= 45 { return .orange }
        return .red
    }
    
    private var memoryColor: Color {
        if monitor.currentMemoryMB < 200 { return .green }
        if monitor.currentMemoryMB < 300 { return .orange }
        return .red
    }
    
    private var cpuColor: Color {
        if monitor.currentCPUPercent < 60 { return .green }
        if monitor.currentCPUPercent < 80 { return .orange }
        return .red
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        VStack(spacing: 16) {
            // Real-time Metrics
            metricCard(
                title: "Frame Rate",
                current: String(format: "%.1f FPS", monitor.currentFPS),
                average: String(format: "%.1f avg", monitor.getAverageFPS()),
                icon: "speedometer",
                color: fpsColor,
                good: monitor.currentFPS >= 50
            )
            
            metricCard(
                title: "Memory Usage",
                current: String(format: "%.0f MB", monitor.currentMemoryMB),
                average: String(format: "%.0f avg", monitor.getAverageMemory()),
                icon: "memorychip",
                color: memoryColor,
                good: monitor.currentMemoryMB < 250
            )
            
            metricCard(
                title: "CPU Usage",
                current: String(format: "%.0f%%", monitor.currentCPUPercent),
                average: String(format: "%.0f%% avg", monitor.getAverageCPU()),
                icon: "cpu",
                color: cpuColor,
                good: monitor.currentCPUPercent < 70
            )
            
            // Performance Summary
            summaryCard
        }
        .padding(.horizontal)
    }
    
    private func metricCard(title: String, current: String, average: String, icon: String, color: Color, good: Bool) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(current)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(average)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status
            Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(good ? .green : .orange)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
    }
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Summary")
                .font(.headline)
            
            HStack {
                summaryItem(label: "Issues", value: "\(monitor.performanceIssues.count)")
                Spacer()
                summaryItem(label: "Critical", value: "\(monitor.performanceIssues.filter { $0.severity == .critical }.count)")
                Spacer()
                summaryItem(label: "Warnings", value: "\(monitor.performanceIssues.filter { $0.severity == .warning }.count)")
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
    }
    
    private func summaryItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Views Tab
    
    private var viewsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Slowest Views")
                .font(.headline)
                .padding(.horizontal)
            
            let slowViews = monitor.getSlowestViews().prefix(10)
            
            if slowViews.isEmpty {
                emptyState(message: "No view data yet", icon: "rectangle.stack")
            } else {
                ForEach(Array(slowViews.enumerated()), id: \.offset) { index, view in
                    viewLoadRow(rank: index + 1, name: view.name, avgMs: view.avgMs)
                }
            }
            
            Divider()
                .padding(.vertical)
            
            Text("Slowest Transitions")
                .font(.headline)
                .padding(.horizontal)
            
            let slowTransitions = monitor.getSlowestTransitions().prefix(10)
            
            if slowTransitions.isEmpty {
                emptyState(message: "No transition data yet", icon: "arrow.left.arrow.right")
            } else {
                ForEach(Array(slowTransitions.enumerated()), id: \.offset) { index, transition in
                    transitionRow(rank: index + 1, from: transition.from, to: transition.to, avgMs: transition.avgMs)
                }
            }
        }
    }
    
    private func viewLoadRow(rank: Int, name: String, avgMs: Double) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("#\(rank)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            // View name
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Average load time")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Time
            Text(formatMs(avgMs))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(avgMs > 500 ? .red : avgMs > 300 ? .orange : .green)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func transitionRow(rank: Int, from: String, to: String, avgMs: Double) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("#\(rank)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            // Transition
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(from)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(to)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .lineLimit(1)
                
                Text("Average transition")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Time
            Text(formatMs(avgMs))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(avgMs > 300 ? .red : avgMs > 200 ? .orange : .green)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Issues Tab
    
    private var issuesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if monitor.performanceIssues.isEmpty {
                emptyState(message: "No performance issues detected", icon: "checkmark.circle")
            } else {
                ForEach(monitor.performanceIssues.reversed()) { issue in
                    issueRow(issue)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func issueRow(_ issue: PerformanceIssue) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: issue.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundColor(issue.severity == .critical ? .red : .orange)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.type.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(issue.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(formatTime(issue.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Severity badge
            Text(issue.severity.rawValue.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(issue.severity == .critical ? Color.red : Color.orange)
                .cornerRadius(6)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
    }
    
    // MARK: - Empty State
    
    private func emptyState(message: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Helpers
    
    private func formatMs(_ ms: Double) -> String {
        return "\(Int(ms))ms"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    PerformanceDashboardView()
}
