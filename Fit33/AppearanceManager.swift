import SwiftUI

/// Manages the app's appearance/color scheme settings
class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()
    
    /// The three appearance modes available
    enum AppearanceMode: String, CaseIterable {
        case light = "Light"
        case dark = "Dark"
        case auto = "Auto"
        
        var icon: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .auto: return "circle.lefthalf.filled"
            }
        }
        
        var description: String {
            switch self {
            case .light: return "Always use light mode"
            case .dark: return "Always use dark mode"
            case .auto: return "Follow system settings"
            }
        }
    }
    
    /// The current appearance mode, persisted to UserDefaults
    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }
    
    /// The computed color scheme based on the current mode
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil // nil means follow system
        }
    }
    
    private init() {
        // Load saved preference or default to dark mode
        if let savedMode = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: savedMode) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .dark
        }
    }
    
    /// Apply the appearance to all windows
    func applyAppearance() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            
            for window in windowScene.windows {
                switch self.appearanceMode {
                case .light:
                    window.overrideUserInterfaceStyle = .light
                case .dark:
                    window.overrideUserInterfaceStyle = .dark
                case .auto:
                    window.overrideUserInterfaceStyle = .unspecified
                }
            }
        }
    }
}

