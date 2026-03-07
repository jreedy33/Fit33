import Foundation
import CoreData
import SwiftUI

// MARK: - Personal Record Service
// Detects and celebrates personal records in real-time during workouts

class PersonalRecordService: ObservableObject {
    static let shared = PersonalRecordService()
    
    @Published var newPRsThisSession: [PersonalRecord] = []
    @Published var showingPRCelebration: Bool = false
    @Published var currentPR: PersonalRecord?
    
    private let viewContext = PersistenceController.shared.container.viewContext
    
    private init() {}
    
    // MARK: - Personal Record Model
    
    struct PersonalRecord: Identifiable, Equatable {
        let id = UUID()
        let exerciseName: String
        let type: PRType
        let value: Double
        let previousValue: Double?
        let improvement: Double?
        let date: Date
        
        enum PRType: String, CaseIterable {
            case maxWeight = "Max Weight"
            case maxReps = "Max Reps"
            case maxVolume = "Max Volume"
            case oneRepMax = "Estimated 1RM"
            
            var icon: String {
                switch self {
                case .maxWeight: return "scalemass.fill"
                case .maxReps: return "repeat"
                case .maxVolume: return "chart.bar.fill"
                case .oneRepMax: return "crown.fill"
                }
            }
            
            var color: Color {
                switch self {
                case .maxWeight: return .orange
                case .maxReps: return .blue
                case .maxVolume: return .purple
                case .oneRepMax: return .yellow
                }
            }
        }
        
        var celebrationMessage: String {
            switch type {
            case .maxWeight:
                return "New max weight: \(Int(value)) lbs! 🏋️"
            case .maxReps:
                return "New rep record: \(Int(value)) reps! 💪"
            case .maxVolume:
                return "Best volume ever! 📈"
            case .oneRepMax:
                return "New estimated 1RM: \(Int(value)) lbs! 👑"
            }
        }
    }
    
    // MARK: - PR Detection
    
    /// Check if a completed set is a personal record
    /// Returns the PR if one was achieved, nil otherwise
    func checkForPR(
        exerciseName: String,
        weight: Double,
        reps: Int,
        exerciseId: UUID?
    ) -> PersonalRecord? {
        
        guard weight > 0, reps > 0 else { return nil }
        
        // Fetch historical data for this exercise
        let historicalData = fetchExerciseHistory(exerciseName: exerciseName)
        
        var achievedPRs: [PersonalRecord] = []
        
        // Check for max weight PR (with at least 1 rep)
        let previousMaxWeight = historicalData.maxWeight
        if weight > previousMaxWeight {
            let pr = PersonalRecord(
                exerciseName: exerciseName,
                type: .maxWeight,
                value: weight,
                previousValue: previousMaxWeight > 0 ? previousMaxWeight : nil,
                improvement: previousMaxWeight > 0 ? weight - previousMaxWeight : nil,
                date: Date()
            )
            achievedPRs.append(pr)
        }
        
        // Check for max reps PR (at a meaningful weight - within 80% of max)
        if previousMaxWeight > 0 && weight >= previousMaxWeight * 0.8 {
            let previousMaxReps = historicalData.maxRepsAtWeight(weight: weight, tolerance: 0.1)
            if reps > previousMaxReps {
                let pr = PersonalRecord(
                    exerciseName: exerciseName,
                    type: .maxReps,
                    value: Double(reps),
                    previousValue: previousMaxReps > 0 ? Double(previousMaxReps) : nil,
                    improvement: previousMaxReps > 0 ? Double(reps - previousMaxReps) : nil,
                    date: Date()
                )
                achievedPRs.append(pr)
            }
        }
        
        // Check for estimated 1RM PR (Brzycki formula)
        let current1RM = calculate1RM(weight: weight, reps: reps)
        let previous1RM = historicalData.estimated1RM
        if current1RM > previous1RM && current1RM > 0 {
            let pr = PersonalRecord(
                exerciseName: exerciseName,
                type: .oneRepMax,
                value: current1RM,
                previousValue: previous1RM > 0 ? previous1RM : nil,
                improvement: previous1RM > 0 ? current1RM - previous1RM : nil,
                date: Date()
            )
            achievedPRs.append(pr)
        }
        
        // Return the most significant PR (prefer 1RM > maxWeight > maxReps)
        if let bestPR = achievedPRs.first(where: { $0.type == .oneRepMax }) ??
                        achievedPRs.first(where: { $0.type == .maxWeight }) ??
                        achievedPRs.first {
            recordPR(bestPR)
            return bestPR
        }
        
        return nil
    }
    
    /// Record PR and trigger celebration
    private func recordPR(_ pr: PersonalRecord) {
        // Log the personal record
        SessionLogManager.shared.logPersonalRecord(
            exerciseName: pr.exerciseName,
            metric: pr.type.rawValue,
            oldValue: pr.previousValue ?? 0,
            newValue: pr.value,
            improvement: pr.improvement ?? pr.value
        )
        
        DispatchQueue.main.async {
            self.newPRsThisSession.append(pr)
            self.currentPR = pr
            self.showingPRCelebration = true
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Auto-hide celebration after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.showingPRCelebration = false
            }
            
            // Award league points for PR (+30 pts)
            Task { @MainActor in
                await WeeklyLeagueService.shared.addPoints(source: .personalRecord)
                
                // Update daily quest progress for PR
                await DailyQuestService.shared.onPersonalRecord()
            }
            
            #if DEBUG
            print("🏆 NEW PR ACHIEVED: \(pr.celebrationMessage)")
            #endif
        }
    }
    
    /// Calculate estimated 1RM using Brzycki formula
    private func calculate1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0, reps <= 12, weight > 0 else { return 0 }
        // Brzycki formula: 1RM = weight × (36 / (37 - reps))
        return weight * (36.0 / (37.0 - Double(reps)))
    }
    
    // MARK: - Historical Data
    
    struct ExerciseHistoricalData {
        var maxWeight: Double = 0
        var maxReps: Int = 0
        var estimated1RM: Double = 0
        var setHistory: [(weight: Double, reps: Int, date: Date)] = []
        
        func maxRepsAtWeight(weight: Double, tolerance: Double) -> Int {
            let matchingSets = setHistory.filter { 
                abs($0.weight - weight) / max(weight, 1) <= tolerance 
            }
            return matchingSets.map { $0.reps }.max() ?? 0
        }
    }
    
    private func fetchExerciseHistory(exerciseName: String) -> ExerciseHistoricalData {
        var data = ExerciseHistoricalData()
        
        // Fetch all completed sets for this exercise
        let request: NSFetchRequest<WorkoutSet> = WorkoutSet.fetchRequest()
        request.predicate = NSPredicate(
            format: "workoutExercise.exercise.name == %@ AND isCompleted == YES",
            exerciseName
        )
        
        do {
            let sets = try viewContext.fetch(request)
            
            for set in sets {
                let weight = set.weight
                let reps = Int(set.reps)
                let date = set.workoutExercise?.workout?.date ?? Date()
                
                // Track max weight
                if weight > data.maxWeight {
                    data.maxWeight = weight
                }
                
                // Track max reps overall
                if reps > data.maxReps {
                    data.maxReps = reps
                }
                
                // Track estimated 1RM
                let set1RM = calculate1RM(weight: weight, reps: reps)
                if set1RM > data.estimated1RM {
                    data.estimated1RM = set1RM
                }
                
                // Store for detailed analysis
                data.setHistory.append((weight: weight, reps: reps, date: date))
            }
        } catch {
            print("❌ Error fetching exercise history: \(error)")
        }
        
        return data
    }
    
    // MARK: - Session Management
    
    /// Reset PRs for new workout session
    func startNewSession() {
        newPRsThisSession.removeAll()
        currentPR = nil
        showingPRCelebration = false
    }
    
    /// Get summary of PRs achieved in current session
    func getSessionSummary() -> (count: Int, types: [PersonalRecord.PRType]) {
        let count = newPRsThisSession.count
        let types = Array(Set(newPRsThisSession.map { $0.type }))
        return (count, types)
    }
}

// MARK: - PR Celebration View

struct PRCelebrationOverlay: View {
    @ObservedObject var prService = PersonalRecordService.shared
    
    var body: some View {
        ZStack {
            if prService.showingPRCelebration, let pr = prService.currentPR {
                // Dimmed background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        prService.showingPRCelebration = false
                    }
                
                // PR Card
                VStack(spacing: 16) {
                    // Trophy icon with glow
                    ZStack {
                        Circle()
                            .fill(pr.type.color.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .blur(radius: 20)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [pr.type.color, pr.type.color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                            .shadow(color: pr.type.color.opacity(0.5), radius: 15, x: 0, y: 5)
                        
                        Image(systemName: pr.type.icon)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // NEW PR text
                    Text("NEW PR!")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [pr.type.color, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    // Exercise name
                    Text(pr.exerciseName)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    // PR value
                    Text(pr.celebrationMessage)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    // Improvement badge
                    if let improvement = pr.improvement, improvement > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.green)
                            Text("+\(Int(improvement)) \(pr.type == .maxReps ? "reps" : "lbs")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.15))
                        )
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xl)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.xl)
                                .stroke(
                                    LinearGradient(
                                        colors: [pr.type.color.opacity(0.5), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: pr.type.color.opacity(0.3), radius: 30, x: 0, y: 15)
                )
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: prService.showingPRCelebration)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: prService.showingPRCelebration)
    }
}

// MARK: - PR Badge for Exercise Cards

struct PRIndicatorBadge: View {
    let prCount: Int
    
    var body: some View {
        if prCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10))
                Text(prCount == 1 ? "PR!" : "\(prCount) PRs!")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .orange.opacity(0.4), radius: 4, x: 0, y: 2)
            )
        }
    }
}

