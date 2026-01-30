import SwiftUI
import GoogleMobileAds

/// Manages interstitial ads for the workout app
/// Ads are shown between sets during the rest timer for FREE users only
/// Premium users will never see ads
class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()
    
    // MARK: - Published Properties
    
    /// Whether ads are enabled (for testing toggle in settings)
    /// Note: Premium users will never see ads regardless of this setting
    @Published var adsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adsEnabled, forKey: "adsEnabled")
            if adsEnabled && isSDKInitialized && !PremiumManager.shared.isPremiumUser {
                loadInterstitialAd()
            }
        }
    }
    
    /// Whether an ad is currently being shown
    @Published var isShowingAd = false
    
    /// Whether an ad is ready to be shown
    @Published var isAdReady = false
    
    /// Minimum ad duration in seconds (used for timer calculation when no ad plays)
    let minimumAdDuration: TimeInterval = 30
    
    /// The actual duration of the last ad shown (for timer calculation)
    /// Access this from main thread only
    var lastAdDuration: TimeInterval = 0
    
    // MARK: - Private Properties
    
    private var interstitialAd: InterstitialAd?
    private var adStartTime: Date?
    private var onAdDismissed: (() -> Void)?
    private var isSDKInitialized = false
    
    // Ad Unit IDs
    // Test ID: ca-app-pub-3940256099942544/4411468910 (use during development)
    // Production ID: ca-app-pub-8809892203317185/3674561599 (use for release)
    #if DEBUG
    private let adUnitID = "ca-app-pub-3940256099942544/4411468910" // Test ads for development
    #else
    private let adUnitID = "ca-app-pub-8809892203317185/3674561599" // Production ads for release
    #endif
    
    // MARK: - Initialization
    
    private override init() {
        // Default to true if not previously set
        if UserDefaults.standard.object(forKey: "adsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "adsEnabled")
        }
        self.adsEnabled = UserDefaults.standard.bool(forKey: "adsEnabled")
        super.init()
        
        // Don't initialize SDK here - wait until app is ready
        print("📺 AdManager created, SDK will initialize when needed")
    }
    
    /// Initialize the Google Mobile Ads SDK
    /// This is called lazily - only when an ad is about to be needed (e.g., starting a workout)
    /// NOT at app startup to avoid 14+ second WebView delays
    private var sdkInitStartTime: Date?
    
    func initializeSDK() {
        print("📺 [SDK] initializeSDK called - isSDKInitialized: \(isSDKInitialized)")
        guard !isSDKInitialized else {
            print("📺 [SDK] Already initialized, skipping")
            return
        }
        
        // Check premium status
        let isPremium = PremiumManager.shared.isPremiumUser
        print("📺 [SDK] isPremiumUser: \(isPremium)")
        
        // Premium users don't need ads SDK
        guard !isPremium else {
            print("📺 [SDK] Premium user, skipping SDK initialization")
            return
        }
        
        print("📺 [SDK] adsEnabled: \(adsEnabled)")
        guard adsEnabled else {
            print("📺 [SDK] Ads disabled, skipping SDK initialization")
            return
        }
        
        print("📺 [SDK] ✅ All checks passed, initializing AdMob SDK...")
        sdkInitStartTime = Date()
        
        MobileAds.shared.start { [weak self] status in
            let initDuration = Int((Date().timeIntervalSince(self?.sdkInitStartTime ?? Date())) * 1000)
            print("📺 AdMob SDK initialized")
            SessionLogManager.shared.logAdSDKInitialized(durationMs: initDuration)
            
            for (adapter, state) in status.adapterStatusesByClassName {
                print("📺 Adapter: \(adapter) - \(state.state.rawValue == 1 ? "Ready" : "Not Ready")")
            }
            
            self?.isSDKInitialized = true
            
            // Preload first ad if ads are enabled
            if self?.adsEnabled == true {
                self?.loadInterstitialAd()
            }
        }
    }
    
    /// Prepare ads before they're needed (call when user is about to start a workout)
    /// This gives the SDK time to initialize and load an ad in the background
    func prepareForWorkout() {
        // Premium users don't need ads
        guard !PremiumManager.shared.isPremiumUser else { return }
        guard adsEnabled else { return }
        
        if !isSDKInitialized {
            print("📺 Preparing ads for workout...")
            initializeSDK()
        } else if !isAdReady {
            loadInterstitialAd()
        }
    }
    
    // MARK: - Public Methods
    
    private var adLoadStartTime: Date?
    
    /// Load a new interstitial ad
    func loadInterstitialAd() {
        // Premium users don't need ads
        guard !PremiumManager.shared.isPremiumUser else { return }
        guard adsEnabled else { return }
        
        // Initialize SDK if not already done
        if !isSDKInitialized {
            initializeSDK()
            return
        }
        
        print("📺 Loading interstitial ad...")
        adLoadStartTime = Date()
        
        InterstitialAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            let loadTime = Int((Date().timeIntervalSince(self?.adLoadStartTime ?? Date())) * 1000)
            
            if let error = error {
                print("📺 Failed to load interstitial ad: \(error.localizedDescription)")
                SessionLogManager.shared.logAdLoad(success: false, adUnitId: self?.adUnitID ?? "", loadTimeMs: loadTime, error: error.localizedDescription)
                DispatchQueue.main.async {
                    self?.isAdReady = false
                }
                return
            }
            
            print("📺 Interstitial ad loaded successfully")
            SessionLogManager.shared.logAdLoad(success: true, adUnitId: self?.adUnitID ?? "", loadTimeMs: loadTime)
            self?.interstitialAd = ad
            self?.interstitialAd?.fullScreenContentDelegate = self
            
            DispatchQueue.main.async {
                self?.isAdReady = true
            }
        }
    }
    
    /// Show an interstitial ad after completing a set
    /// - Parameters:
    ///   - viewController: The view controller to present the ad from
    ///   - completion: Called when the ad is dismissed (either naturally or after minimum duration)
    func showInterstitialAd(from viewController: UIViewController, completion: @escaping () -> Void) {
        // Premium users never see ads
        guard !PremiumManager.shared.isPremiumUser else {
            print("📺 Premium user, skipping ad")
            completion()
            return
        }
        
        guard adsEnabled else {
            print("📺 Ads disabled, skipping ad")
            completion()
            return
        }
        
        guard let interstitialAd = interstitialAd else {
            print("📺 No ad available, loading new one")
            SessionLogManager.shared.logAdError(adUnitId: adUnitID, error: "No ad available", context: "showInterstitialAd")
            loadInterstitialAd()
            completion()
            return
        }
        
        print("📺 Showing interstitial ad")
        SessionLogManager.shared.logAdShow(adUnitId: adUnitID, placement: "rest_timer")
        self.onAdDismissed = completion
        self.adStartTime = Date()
        
        DispatchQueue.main.async {
            self.isShowingAd = true
            interstitialAd.present(from: viewController)
        }
    }
    
    /// Check if an ad should be shown (for free users with ads enabled)
    func shouldShowAd() -> Bool {
        // Premium users never see ads
        if PremiumManager.shared.isPremiumUser {
            print("📺 Premium user - no ads")
            return false
        }
        
        print("📺 shouldShowAd check: adsEnabled=\(adsEnabled), isAdReady=\(isAdReady), isSDKInitialized=\(isSDKInitialized)")
        if !adsEnabled {
            print("📺 Ads are disabled in settings")
            return false
        }
        if !isAdReady {
            print("📺 Ad not ready - will load in background for next time")
            // Load in background - don't block the current check
            Task.detached(priority: .background) {
                await MainActor.run {
                    self.loadInterstitialAd()
                }
            }
            return false // Not ready now, but will be for next exercise
        }
        return true
    }
}

// MARK: - FullScreenContentDelegate

extension AdManager: FullScreenContentDelegate {
    
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("📺 Ad recorded impression")
    }
    
    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        print("📺 Ad recorded click")
        SessionLogManager.shared.logAdClicked(adUnitId: adUnitID)
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("📺 Ad failed to present: \(error.localizedDescription)")
        SessionLogManager.shared.logAdError(adUnitId: adUnitID, error: error.localizedDescription, context: "present")
        DispatchQueue.main.async {
            self.isShowingAd = false
            self.isAdReady = false
            self.onAdDismissed?()
            self.onAdDismissed = nil
        }
        // Try to load a new ad
        loadInterstitialAd()
    }
    
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("📺 Ad will present")
    }
    
    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("📺 Ad will dismiss")
    }
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("📺 Ad dismissed")
        
        // Calculate how long the ad was shown and ROUND to whole seconds
        let rawDuration = Date().timeIntervalSince(adStartTime ?? Date())
        let roundedDuration = round(rawDuration)
        print("📺 Ad was shown for \(rawDuration)s (raw) → \(roundedDuration)s (rounded)")
        
        // Log the ad dismissal with watch duration
        SessionLogManager.shared.logAdDismissed(adUnitId: adUnitID, watchedDurationMs: Int(rawDuration * 1000))
        
        // Store the ROUNDED ad duration for the rest timer calculation
        lastAdDuration = roundedDuration
        
        // IMMEDIATELY call completion - don't wait for minimum duration
        // The rest timer will account for the actual ad time shown
        DispatchQueue.main.async {
            self.isShowingAd = false
            self.isAdReady = false
            print("📺 Calling ad completion callback...")
            self.onAdDismissed?()
            self.onAdDismissed = nil
            print("📺 Ad completion callback finished")
        }
        
        // Preload the next ad
        loadInterstitialAd()
    }
}

// MARK: - SwiftUI Helper

/// A helper to get the root view controller for presenting ads
struct RootViewControllerFinder {
    static func find() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        
        var topController = window.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        
        return topController
    }
}
