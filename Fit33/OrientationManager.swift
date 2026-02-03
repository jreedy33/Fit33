import SwiftUI
import Combine

/// Global orientation manager that observes device orientation changes
/// and provides updated screen dimensions to all views
class OrientationManager: ObservableObject {
    static let shared = OrientationManager()
    
    /// Current screen width (updates on rotation)
    @Published var screenWidth: CGFloat = UIScreen.main.bounds.width
    
    /// Current screen height (updates on rotation)
    @Published var screenHeight: CGFloat = UIScreen.main.bounds.height
    
    /// Current screen size (updates on rotation)
    @Published var screenSize: CGSize = UIScreen.main.bounds.size
    
    /// Whether the device is in landscape orientation
    @Published var isLandscape: Bool = UIScreen.main.bounds.width > UIScreen.main.bounds.height
    
    /// Current safe area insets
    @Published var safeAreaInsets: EdgeInsets = EdgeInsets()
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Observe orientation changes - use shorter debounce for faster response
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateScreenDimensions()
            }
            .store(in: &cancellables)
        
        // Also observe when the app becomes active (handles rotation while backgrounded)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.updateScreenDimensions()
            }
            .store(in: &cancellables)
        
        // Observe when trait collection changes (handles split view, etc.)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.updateScreenDimensions()
                }
            }
            .store(in: &cancellables)
        
        // 📱 Also observe UIWindowScene notifications for more reliable orientation detection
        NotificationCenter.default.publisher(for: UIScene.willEnterForegroundNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
        // Ensure we're on main thread for UI updates
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.performScreenUpdate()
            }
        } else {
            performScreenUpdate()
        }
    }
    
    private func performScreenUpdate() {
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
