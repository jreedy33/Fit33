import SwiftUI
import Combine

// MARK: - GO Button State (Singleton)
class GoButtonState: ObservableObject {
    static let shared = GoButtonState()
    @Published var isVisible: Bool = false {
        didSet {
            // Post notification for non-reactive observers
            NotificationCenter.default.post(name: .goButtonVisibilityChanged, object: isVisible)
        }
    }
    private var startAction: (() -> Void)? = nil
    private var isTriggering: Bool = false // Prevent double-triggers
    private var showVersion: Int = 0 // Track show/hide cycles to prevent race conditions
    var primaryColor: Color = Color(red: 0.2, green: 0.7, blue: 0.3)
    var secondaryColor: Color = Color(red: 0.15, green: 0.55, blue: 0.85)
    var accessibilityText: String = "Start workout"
    
    // Tracking
    private var showTime: Date?
    private var showSource: String = ""
    
    private init() {}
    
    func show(primaryColor: Color = Color(red: 0.2, green: 0.7, blue: 0.3),
              secondaryColor: Color? = nil,
              accessibilityText: String = "Start workout",
              source: String = "unknown",
              action: @escaping () -> Void) {
        AppLogger.debug("[GoButton] show() called", category: .ui)
        showTime = Date()
        showSource = source
        
        // Log to session manager
        SessionLogManager.shared.logGoButtonShow(frame: nil)
        SessionLogManager.shared.log(.info, category: .userAction, message: "🟢 GO! SHOW", metadata: [
            "source": source,
            "element_id": "E200"
        ])
        
        // Reset state completely when showing
        self.isTriggering = false
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor ?? primaryColor.opacity(0.7)
        self.accessibilityText = accessibilityText
        self.startAction = action
        self.showVersion += 1 // Increment version to invalidate pending hide() calls
        
        DispatchQueue.main.async {
            self.isVisible = true
            AppLogger.debug("[GoButton] isVisible = true", category: .ui)
        }
    }
    
    func hide(reason: String = "navigation") {
        AppLogger.debug("[GoButton] hide() called", category: .ui)
        
        // Calculate visible duration
        var visibleMs: Int = 0
        if let start = showTime {
            visibleMs = Int(Date().timeIntervalSince(start) * 1000)
        }
        
        // Log to session manager
        SessionLogManager.shared.logGoButtonHide(reason: reason)
        SessionLogManager.shared.log(.info, category: .userAction, message: "🔴 GO! HIDE", metadata: [
            "reason": reason,
            "visible_ms": visibleMs,
            "source": showSource,
            "element_id": "E200"
        ])
        
        // Capture current version to check in async block
        let hideVersion = self.showVersion
        
        DispatchQueue.main.async {
            self.isVisible = false
            self.isTriggering = false // Reset triggering state
            
            // Only clear action if no new show() was called since this hide() was initiated
            // This prevents race condition where show() sets action, then pending hide() clears it
            if self.showVersion == hideVersion {
                self.startAction = nil
                AppLogger.debug("[GoButton] Hidden and cleared", category: .ui)
            } else {
                AppLogger.debug("[GoButton] Hidden but action preserved (new show() pending)", category: .ui)
            }
        }
    }
    
    func triggerStart() {
        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.debug("[GoButton] triggerStart() BEGIN", category: .ui)
        
        // Calculate response time (how long user took to tap)
        var responseMs: Int = 0
        if let start = showTime {
            responseMs = Int(Date().timeIntervalSince(start) * 1000)
        }
        
        // Log tap to session manager
        SessionLogManager.shared.logGoButtonTap(tapPoint: nil)
        SessionLogManager.shared.log(.info, category: .userAction, message: "👆 GO! TAP", metadata: [
            "response_time_ms": responseMs,
            "source": showSource,
            "element_id": "E200"
        ])
        
        // Prevent double-triggers
        guard !isTriggering else {
            AppLogger.warning("[GoButton] Already triggering, ignoring duplicate call", category: .ui)
            SessionLogManager.shared.log(.warning, category: .userAction, message: "⚠️ GO! DOUBLE TAP BLOCKED")
            return
        }
        
        // Capture action before any state changes
        guard let action = startAction else {
            AppLogger.error("[GoButton] No startAction set!", category: .ui)
            SessionLogManager.shared.log(.error, category: .error, message: "❌ GO! NO ACTION", metadata: [
                "element_id": "E200"
            ])
            return
        }
        
        // Mark as triggering and hide button immediately
        isTriggering = true
        isVisible = false
        
        AppLogger.debug("[GoButton] Executing action...", category: .ui)
        let actionStart = CFAbsoluteTimeGetCurrent()
        
        // Execute action synchronously
        action()
        
        let actionDuration = (CFAbsoluteTimeGetCurrent() - actionStart) * 1000
        let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        AppLogger.debug("[GoButton] Action took: \(actionDuration)ms", category: .ui)
        AppLogger.debug("[GoButton] TOTAL: \(totalDuration)ms", category: .ui)
        
        // Log timing
        SessionLogManager.shared.log(.info, category: .userAction, message: "⏱️ GO! ACTION COMPLETE", metadata: [
            "action_duration_ms": Int(actionDuration),
            "total_duration_ms": Int(totalDuration),
            "element_id": "E200"
        ])
        
        // Flag slow action
        if actionDuration > 500 {
            SessionLogManager.shared.log(.warning, category: .userAction, message: "🐢 GO! SLOW ACTION", metadata: [
                "duration_ms": Int(actionDuration),
                "element_id": "E200"
            ])
        }
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.startAction = nil
            self?.isTriggering = false
            AppLogger.debug("[GoButton] State reset complete", category: .ui)
        }
    }
}

// Isolated overlay view - only this re-renders when GoButtonState changes
struct GoButtonOverlay: View {
    @ObservedObject var state = GoButtonState.shared
    
    var body: some View {
        if state.isVisible {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingGoButton(
                        action: { state.triggerStart() },
                        primaryColor: state.primaryColor,
                        secondaryColor: state.secondaryColor,
                        accessibilityText: state.accessibilityText
                    )
                    .offset(x: 3, y: 2) // Fine-tune centering between Exercises and Meals tabs
                    Spacer()
                }
                .padding(.bottom, 18) // Align bottom of button with bottom of tab icons
            }
            .ignoresSafeArea(.keyboard)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.1), value: state.isVisible)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Home Badge Counter (Combine-based, prevents render cascade)
// ═══════════════════════════════════════════════════════════════════════════════
/// Lightweight counter that tracks ONLY the Home tab badge count via Combine.
///
/// 🔴 WHY THIS EXISTS:
/// Previously, MainTabView directly observed FriendService (12 @Published),
/// ChallengeService (8 @Published), and PrivateChallengeService (4 @Published).
/// ANY change to ANY of those 24 properties forced a full re-render of ALL 5 tab
/// views — causing catastrophic render cascades during HealthKit sync.
///
/// This class subscribes to only the 5 specific properties needed for the badge
/// and uses .removeDuplicates() so MainTabView ONLY re-renders when the actual
/// badge count changes.
@MainActor
final class HomeBadgeCounter: ObservableObject {
    static let shared = HomeBadgeCounter()
    @Published private(set) var count: Int = 0
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let friendPending = FriendService.shared.$pendingRequests
            .map(\.count)
        let friendWorkouts = FriendService.shared.$receivedWorkouts
            .map { $0.filter { $0.viewedAt == nil && $0.isPending }.count }
        let challengeInvites = ChallengeService.shared.$pendingInvites
            .map(\.count)
        let groupInvites = ChallengeService.shared.$activeGroupChallenges
            .map { $0.filter(\.isMyInvitePending).count }
        let privateInvites = PrivateChallengeService.shared.$pendingInvites
            .map(\.count)
        
        Publishers.CombineLatest3(friendPending, friendWorkouts, challengeInvites)
            .combineLatest(Publishers.CombineLatest(groupInvites, privateInvites))
            .map { triple, pair in triple.0 + triple.1 + triple.2 + pair.0 + pair.1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.count = $0 }
            .store(in: &cancellables)
    }
}
