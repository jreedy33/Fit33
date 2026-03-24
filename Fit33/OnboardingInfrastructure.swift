import SwiftUI
import Combine

// MARK: - Keyboard Height Observer
class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] height in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.keyboardHeight = height
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.keyboardHeight = 0
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Onboarding Session Manager
// Tracks onboarding session for debugging
class OnboardingSessionManager: ObservableObject {
    static let shared = OnboardingSessionManager()
    
    @Published var currentSessionId: String?
    @Published var sessionStartTime: Date?
    
    private var stepTimestamps: [Int: Date] = [:]
    private var stepDurations: [Int: TimeInterval] = [:]
    
    private static let checkpointStepKey = "onboarding_checkpoint_step"
    private static let checkpointDataKey = "onboarding_checkpoint_data"
    
    private init() {}
    
    func startNewSession() {
        currentSessionId = UUID().uuidString
        sessionStartTime = Date()
        stepTimestamps = [:]
        stepDurations = [:]
        AppLogger.info("Onboarding session started: \(currentSessionId ?? "nil")", category: .ui)
    }
    
    func trackStepStarted(_ stepIndex: Int) {
        stepTimestamps[stepIndex] = Date()
    }
    
    func trackStepCompleted(_ stepIndex: Int) {
        if let started = stepTimestamps[stepIndex] {
            stepDurations[stepIndex] = Date().timeIntervalSince(started)
        }
    }
    
    func endSession() {
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            AppLogger.info("Onboarding session ended. Duration: \(Int(duration))s", category: .ui)
            for (step, dur) in stepDurations.sorted(by: { $0.key < $1.key }) {
                AppLogger.debug("Onboarding step \(step): \(String(format: "%.1f", dur))s", category: .ui)
            }
        }
        currentSessionId = nil
        sessionStartTime = nil
    }
    
    var sessionDuration: TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - Progress Persistence
    
    func saveCheckpoint(step: Int, data: [String: String]) {
        UserDefaults.standard.set(step, forKey: Self.checkpointStepKey)
        UserDefaults.standard.set(data, forKey: Self.checkpointDataKey)
    }
    
    func loadCheckpoint() -> (step: Int, data: [String: String])? {
        let step = UserDefaults.standard.integer(forKey: Self.checkpointStepKey)
        guard step > 0 else { return nil }
        let data = UserDefaults.standard.dictionary(forKey: Self.checkpointDataKey) as? [String: String] ?? [:]
        return (step: step, data: data)
    }
    
    func clearCheckpoint() {
        UserDefaults.standard.removeObject(forKey: Self.checkpointStepKey)
        UserDefaults.standard.removeObject(forKey: Self.checkpointDataKey)
    }
}
