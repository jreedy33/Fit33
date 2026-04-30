import SwiftUI

// Data models
struct PreviousSetData {
    let setNumber: Int
    let weight: Double
    let reps: Int
    var isSmartRecommendation: Bool = false  // True if this is an AI-generated recommendation
    var recommendationNote: String? = nil    // Optional note about the recommendation
    
    var displayString: String {
        if weight > 0 && reps > 0 {
            // Format weight to preserve decimals (e.g., 187.5)
            let weightStr = weight.truncatingRemainder(dividingBy: 1) == 0 
                ? "\(Int(weight))" 
                : String(format: "%.1f", weight)
            if isSmartRecommendation {
                return "💡 \(weightStr)×\(reps)"  // Smart recommendation indicator
            }
            return "\(weightStr)×\(reps)"
        }
        return "-"
    }
    
    /// Initialize from historical data
    init(setNumber: Int, weight: Double, reps: Int) {
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.isSmartRecommendation = false
        self.recommendationNote = nil
    }
    
    /// Initialize from smart recommendation
    init(setNumber: Int, recommendation: StrengthProfileRecommendationEngine.SmartRecommendation) {
        self.setNumber = setNumber
        self.weight = recommendation.weight
        self.reps = recommendation.reps
        self.isSmartRecommendation = true
        self.recommendationNote = recommendation.adjustmentNote
    }
}

// MARK: - Set Type Enum
enum SetType: String, CaseIterable, Codable {
    case normal = "Normal"
    case warmup = "Warmup"
    case dropset = "Dropset"
    case failure = "Failure"
    case amrap = "AMRAP"       // As Many Reps As Possible
    case pause = "Pause Rep"   // Pause at bottom/top
    case tempo = "Tempo"       // Slow/controlled tempo
    
    /// Display letter for the set row
    var displayLetter: String? {
        switch self {
        case .normal: return nil  // Show number instead
        case .warmup: return "W"
        case .dropset: return "D"
        case .failure: return "F"
        case .amrap: return "A"
        case .pause: return "P"
        case .tempo: return "T"
        }
    }
    
    /// Color for the set type indicator
    var color: Color {
        switch self {
        case .normal: return .primary
        case .warmup: return .orange
        case .dropset: return .purple
        case .failure: return .red
        case .amrap: return .green
        case .pause: return .cyan
        case .tempo: return .blue
        }
    }
    
    /// Icon for the menu
    var icon: String {
        switch self {
        case .normal: return "number.circle"
        case .warmup: return "flame"
        case .dropset: return "arrow.down.circle"
        case .failure: return "exclamationmark.triangle"
        case .amrap: return "infinity.circle"
        case .pause: return "pause.circle"
        case .tempo: return "metronome"
        }
    }
    
    /// Description for the menu
    var description: String {
        switch self {
        case .normal: return "Standard working set"
        case .warmup: return "Light weight warm-up"
        case .dropset: return "Reduce weight, continue reps"
        case .failure: return "Push to muscle failure"
        case .amrap: return "As many reps as possible"
        case .pause: return "Pause at bottom/top"
        case .tempo: return "Slow controlled tempo"
        }
    }
}

class WorkoutSetData: ObservableObject, Identifiable {
    let id = UUID()
    @Published var weight: Double = 0       // Always stored in lbs
    @Published var weightKg: Double = 0     // Always stored in kg
    @Published var reps: Int = 0
    @Published var isCompleted: Bool = false {
        didSet {
            // Capture wall-clock at moment-of-completion so the analysis
            // pipeline can derive set-pacing without reverse-engineering
            // (workout.duration / completed_sets). Cleared on uncheck.
            if isCompleted {
                if completedAt == nil { completedAt = Date() }
            } else {
                completedAt = nil
            }
        }
    }
    @Published var completedAt: Date? = nil
    @Published var setType: SetType = .normal
    @Published var restTime: TimeInterval = 0
    
    static let lbsToKg = 0.453592
    static let kgToLbs = 2.20462
    
    func syncWeightUnits(fromLbs: Bool = true) {
        if fromLbs {
            weightKg = (weight * Self.lbsToKg * 10).rounded() / 10
        } else {
            weight = (weightKg * Self.kgToLbs * 10).rounded() / 10
        }
    }
    
    // Legacy computed properties for backwards compatibility
    var isFailure: Bool {
        get { setType == .failure }
        set { if newValue { setType = .failure } else if setType == .failure { setType = .normal } }
    }
    
    var isDropset: Bool {
        get { setType == .dropset }
        set { if newValue { setType = .dropset } else if setType == .dropset { setType = .normal } }
    }
    
    var isWarmup: Bool {
        get { setType == .warmup }
        set { if newValue { setType = .warmup } else if setType == .warmup { setType = .normal } }
    }
}
