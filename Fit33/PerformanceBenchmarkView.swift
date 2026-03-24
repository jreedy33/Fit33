#if DEBUG
import SwiftUI

struct PerformanceBenchmarkView: View {
    @State private var metrics: [BenchmarkMetric] = []
    @State private var isRunning = false
    
    var body: some View {
        List {
            Section("Performance Targets") {
                ForEach(metrics) { metric in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.name)
                                .font(.system(size: 14, weight: .semibold))
                            Text(metric.detail)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(metric.value)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(metric.passed ? .green : .red)
                        Image(systemName: metric.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(metric.passed ? .green : .red)
                    }
                }
            }
            
            Section {
                Button(isRunning ? "Running..." : "Run Benchmark") {
                    runBenchmark()
                }
                .disabled(isRunning)
            }
        }
        .navigationTitle("Performance")
        .onAppear { runBenchmark() }
    }
    
    private func runBenchmark() {
        isRunning = true
        var results: [BenchmarkMetric] = []
        
        let memoryMB = Double(os_proc_available_memory()) / 1_048_576
        let totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let usedMemoryMB = (totalMemoryGB * 1024) - memoryMB
        
        results.append(BenchmarkMetric(
            name: "Memory Usage",
            detail: "Target: <200MB at idle",
            value: "\(Int(usedMemoryMB))MB",
            passed: usedMemoryMB < 200
        ))
        
        results.append(BenchmarkMetric(
            name: "Free Memory",
            detail: "Available to app",
            value: "\(Int(memoryMB))MB",
            passed: memoryMB > 200
        ))
        
        let exerciseCount = ExerciseLibraryService.shared.getAllExercises().count
        results.append(BenchmarkMetric(
            name: "Exercise Library",
            detail: "Cached exercises ready",
            value: "\(exerciseCount)",
            passed: exerciseCount > 5000
        ))
        
        let friendCount = FriendService.shared.friends.count
        results.append(BenchmarkMetric(
            name: "Friends Cached",
            detail: "Instant display on Friends tab",
            value: "\(friendCount)",
            passed: friendCount > 0
        ))
        
        let challengeCount = ChallengeService.shared.activeChallenges.count
        results.append(BenchmarkMetric(
            name: "Challenges Cached",
            detail: "Instant display on Dashboard",
            value: "\(challengeCount)",
            passed: true
        ))
        
        let thermalState: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = "Nominal"
        case .fair: thermalState = "Fair"
        case .serious: thermalState = "Serious"
        case .critical: thermalState = "Critical"
        @unknown default: thermalState = "Unknown"
        }
        results.append(BenchmarkMetric(
            name: "Thermal State",
            detail: "Device heat level",
            value: thermalState,
            passed: ProcessInfo.processInfo.thermalState.rawValue < 2
        ))
        
        results.append(BenchmarkMetric(
            name: "Low Power Mode",
            detail: "Affects performance",
            value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "OFF",
            passed: !ProcessInfo.processInfo.isLowPowerModeEnabled
        ))
        
        let threadCount = Thread.isMainThread ? "main" : "background"
        results.append(BenchmarkMetric(
            name: "Current Thread",
            detail: "Should be main for UI",
            value: threadCount,
            passed: Thread.isMainThread
        ))
        
        metrics = results
        isRunning = false
    }
}

struct BenchmarkMetric: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let value: String
    let passed: Bool
}
#endif
