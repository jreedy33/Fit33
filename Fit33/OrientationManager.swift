import SwiftUI
import Combine

// MARK: - Device Tier

enum DeviceTier: String {
    case compact   // iPhone SE (375pt and below)
    case standard  // iPhone 14/15/16 (376-399pt)
    case large     // iPhone Plus/Pro Max (400-450pt)
    case tablet    // All iPads (451pt+)

    static var current: DeviceTier {
        let width = OrientationManager.shared.screenWidth
        switch width {
        case ...375: return .compact
        case 376...399: return .standard
        case 400...450: return .large
        default: return .tablet
        }
    }

    var spacingScale: CGFloat {
        switch self {
        case .compact: return 0.85
        case .standard: return 1.0
        case .large: return 1.1
        case .tablet: return 1.25
        }
    }

    var isTablet: Bool { self == .tablet }
    var isCompact: Bool { self == .compact }
}

/// Global orientation manager that observes device orientation changes
/// and provides updated screen dimensions to all views
/// Thread-safe singleton - all UIKit calls are dispatched to main thread
class OrientationManager: ObservableObject {
    // Swift's static let is inherently thread-safe (uses dispatch_once)
    static let shared = OrientationManager()
    
    /// Current screen width (updates on rotation) - defaults to iPhone 15 Pro width
    @Published var screenWidth: CGFloat = 393
    
    /// Current screen height (updates on rotation) - defaults to iPhone 15 Pro height
    @Published var screenHeight: CGFloat = 852
    
    /// Current screen size (updates on rotation)
    @Published var screenSize: CGSize = CGSize(width: 393, height: 852)
    
    /// Whether the device is in landscape orientation
    @Published var isLandscape: Bool = false
    
    /// Current safe area insets
    @Published var safeAreaInsets: EdgeInsets = EdgeInsets()
    
    var deviceTier: DeviceTier { DeviceTier.current }
    var isTablet: Bool { deviceTier.isTablet }
    var isCompact: Bool { deviceTier.isCompact }
    
    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false
    
    private init() {
        // Don't call UIKit APIs in init - defer to main thread
        // This prevents crashes when singleton is accessed from background thread during app launch
        DispatchQueue.main.async { [weak self] in
            self?.setupInitialValues()
            self?.setupObservers()
        }
    }
    
    private func setupInitialValues() {
        // Safe to call UIKit here - we're guaranteed to be on main thread
        let bounds = UIScreen.main.bounds
        screenWidth = bounds.width
        screenHeight = bounds.height
        screenSize = bounds.size
        isLandscape = bounds.width > bounds.height
        isInitialized = true
    }
    
    private func setupObservers() {
        // Observe orientation changes - use shorter debounce for faster response
        // RunLoop.main scheduler ensures we're on main thread
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateScreenDimensions()
            }
            .store(in: &cancellables)
        
        // Also observe when the app becomes active (handles rotation while backgrounded)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateScreenDimensions()
            }
            .store(in: &cancellables)
        
        // Observe when trait collection changes (handles split view, etc.)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(0.1))
                    self?.updateScreenDimensions()
                }
            }
            .store(in: &cancellables)
        
        // 📱 Also observe UIWindowScene notifications for more reliable orientation detection
        NotificationCenter.default.publisher(for: UIScene.willEnterForegroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(0.1))
                    self?.updateScreenDimensions()
                }
            }
            .store(in: &cancellables)
        
        // Initial update
        updateScreenDimensions()
        updateSafeAreaInsets()
    }
    
    /// Force update screen dimensions (call this from views if needed)
    func updateScreenDimensions() {
        // Ensure we're on main thread for UIKit access
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateScreenDimensions()
            }
            return
        }
        
        guard isInitialized else { return }
        
        // Get the most accurate bounds from the key window scene
        let bounds: CGRect
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            bounds = window.bounds
        } else {
            bounds = UIScreen.main.bounds
        }
        
        // Only update if values actually changed to prevent unnecessary redraws
        if self.screenWidth != bounds.width {
            self.screenWidth = bounds.width
        }
        if self.screenHeight != bounds.height {
            self.screenHeight = bounds.height
        }
        if self.screenSize != bounds.size {
            self.screenSize = bounds.size
        }
        
        let newIsLandscape = bounds.width > bounds.height
        if self.isLandscape != newIsLandscape {
            self.isLandscape = newIsLandscape
        }
        
        self.updateSafeAreaInsets()
    }
    
    private func updateSafeAreaInsets() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }
        
        let insets = window.safeAreaInsets
        let newInsets = EdgeInsets(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
        
        if self.safeAreaInsets != newInsets {
            self.safeAreaInsets = newInsets
        }
    }
}

// MARK: - View Extension for easy access

extension View {
    /// Observes orientation changes and triggers a view update
    func observeOrientation() -> some View {
        self.modifier(OrientationObserverModifier())
    }
}

/// Modifier that ensures view updates on orientation changes
struct OrientationObserverModifier: ViewModifier {
    @StateObject private var orientationManager = OrientationManager.shared
    
    func body(content: Content) -> some View {
        content
            // Force re-render when screen size changes
            .id(orientationManager.screenSize.width)
    }
}

// MARK: - Responsive Width Helper

extension View {
    /// Returns a width that's responsive to orientation changes
    /// - Parameter percentage: Percentage of screen width (0.0 to 1.0)
    func responsiveWidth(_ percentage: CGFloat) -> CGFloat {
        OrientationManager.shared.screenWidth * percentage
    }
}
