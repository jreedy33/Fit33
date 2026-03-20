import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

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
    
    /// Whether an interstitial ad is ready to be shown
    @Published var isAdReady = false
    
    /// Whether a rewarded video ad is ready to be shown
    @Published var isRewardedAdReady = false
    
    /// Minimum ad duration in seconds (used for timer calculation when no ad plays)
    let minimumAdDuration: TimeInterval = 30
    
    /// The actual duration of the last ad shown (for timer calculation)
    /// Access this from main thread only
    var lastAdDuration: TimeInterval = 0
    
    // MARK: - Private Properties
    
    private var interstitialAd: InterstitialAd?
    private var rewardedAd: RewardedAd?
    private var adStartTime: Date?
    private var onAdDismissed: (() -> Void)?
    private var onRewardEarned: (() -> Void)?
    private var isSDKInitialized = false
    
    /// Whether ATT authorization has been resolved (granted or denied)
    private var attResolved = false
    
    /// Tracks whether the currently presenting ad is a rewarded video (vs interstitial)
    private var isShowingRewardedAd = false
    
    // Interstitial Ad Unit IDs
    // Test ID: ca-app-pub-3940256099942544/4411468910 (use during development)
    // Production ID: ca-app-pub-8809892203317185/3674561599 (use for release)
    #if DEBUG
    private let adUnitID = "ca-app-pub-3940256099942544/4411468910" // Test ads for development
    #else
    private let adUnitID = "ca-app-pub-8809892203317185/3674561599" // Production ads for release
    #endif
    
    // Rewarded Ad Unit IDs
    // Test ID: ca-app-pub-3940256099942544/1712485313 (use during development)
    // Production ID: TODO — Create rewarded video unit in AdMob dashboard (publisher: ca-app-pub-8809892203317185)
    #if DEBUG
    private let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313" // Test rewarded ads
    #else
    private let rewardedAdUnitID = "ca-app-pub-8809892203317185/5259396920" // Production rewarded ads
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
        AppLogger.debug("AdManager created, SDK will initialize when needed", category: .general)
    }
    
    /// Initialize the Google Mobile Ads SDK
    /// This is called lazily - only when an ad is about to be needed (e.g., starting a workout)
    /// NOT at app startup to avoid 14+ second WebView delays
    private var sdkInitStartTime: Date?
    
    func initializeSDK() {
        AppLogger.debug("initializeSDK called - isSDKInitialized: \(isSDKInitialized)", category: .general)
        guard !isSDKInitialized else {
            AppLogger.debug("Already initialized, skipping", category: .general)
            return
        }
        
        // Check premium status
        let isPremium = PremiumManager.shared.isPremiumUser
        AppLogger.debug("isPremiumUser: \(isPremium)", category: .general)
        
        // Premium users don't need ads SDK
        guard !isPremium else {
            AppLogger.debug("Premium user, skipping SDK initialization", category: .general)
            return
        }
        
        AppLogger.debug("adsEnabled: \(adsEnabled)", category: .general)
        guard adsEnabled else {
            AppLogger.debug("Ads disabled, skipping SDK initialization", category: .general)
            return
        }
        
        AppLogger.debug("All checks passed, initializing AdMob SDK...", category: .general)
        sdkInitStartTime = Date()
        
        MobileAds.shared.start { [weak self] status in
            let initDuration = Int((Date().timeIntervalSince(self?.sdkInitStartTime ?? Date())) * 1000)
            AppLogger.info("AdMob SDK initialized", category: .general)
            SessionLogManager.shared.logAdSDKInitialized(durationMs: initDuration)
            
            for (adapter, state) in status.adapterStatusesByClassName {
                AppLogger.debug("Adapter: \(adapter) - \(state.state.rawValue == 1 ? "Ready" : "Not Ready")", category: .general)
            }
            
            self?.isSDKInitialized = true
            
            // Preload first ad if ads are enabled
            if self?.adsEnabled == true {
                self?.loadInterstitialAd()
            }
            
            // Also preload rewarded ad if not ready (for daily quest)
            if self?.isRewardedAdReady == false {
                self?.loadRewardedAd()
            }
        }
    }
    
    /// Request App Tracking Transparency authorization, then initialize AdMob.
    /// Must be called when the app is in the foreground (UIApplication.shared.applicationState == .active).
    /// Safe to call multiple times — no-ops once ATT is resolved.
    func requestTrackingAndInitialize() {
        guard !attResolved else {
            if !isSDKInitialized { initializeSDK() }
            return
        }
        
        guard !PremiumManager.shared.isPremiumUser else {
            AppLogger.debug("Premium user, skipping ATT request", category: .general)
            attResolved = true
            return
        }
        
        guard adsEnabled else {
            AppLogger.debug("Ads disabled, skipping ATT request", category: .general)
            attResolved = true
            return
        }
        
        let status = ATTrackingManager.trackingAuthorizationStatus
        
        switch status {
        case .notDetermined:
            AppLogger.debug("Requesting tracking authorization...", category: .general)
            ATTrackingManager.requestTrackingAuthorization { [weak self] authStatus in
                DispatchQueue.main.async {
                    self?.attResolved = true
                    switch authStatus {
                    case .authorized:
                        AppLogger.debug("Tracking authorized — initializing SDK with personalized ads", category: .general)
                    case .denied:
                        AppLogger.debug("Tracking denied — initializing SDK with limited ads", category: .general)
                    case .restricted:
                        AppLogger.debug("Tracking restricted — initializing SDK with limited ads", category: .general)
                    case .notDetermined:
                        AppLogger.debug("ATT status still not determined", category: .general)
                    @unknown default:
                        AppLogger.debug("Unknown ATT status: \(authStatus.rawValue)", category: .general)
                    }
                    self?.initializeSDK()
                }
            }
        case .authorized:
            AppLogger.debug("ATT already authorized", category: .general)
            attResolved = true
            initializeSDK()
        case .denied, .restricted:
            AppLogger.debug("ATT already denied/restricted — will show limited ads", category: .general)
            attResolved = true
            initializeSDK()
        @unknown default:
            AppLogger.debug("Unknown ATT status: \(status.rawValue)", category: .general)
            attResolved = true
            initializeSDK()
        }
    }
    
    /// Prepare ads before they're needed (call when user is about to start a workout)
    /// This gives the SDK time to initialize and load an ad in the background
    func prepareForWorkout() {
        guard !PremiumManager.shared.isPremiumUser else { return }
        guard adsEnabled else { return }
        
        if !isSDKInitialized {
            AppLogger.debug("Preparing ads for workout...", category: .general)
            if attResolved {
                initializeSDK()
            } else {
                requestTrackingAndInitialize()
            }
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
        
        AppLogger.debug("Loading interstitial ad...", category: .general)
        adLoadStartTime = Date()
        
        InterstitialAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            let loadTime = Int((Date().timeIntervalSince(self?.adLoadStartTime ?? Date())) * 1000)
            
            if let error = error {
                AppLogger.error("Failed to load interstitial ad: \(error.localizedDescription)", category: .general)
                SessionLogManager.shared.logAdLoad(success: false, adUnitId: self?.adUnitID ?? "", loadTimeMs: loadTime, error: error.localizedDescription)
                DispatchQueue.main.async {
                    self?.isAdReady = false
                }
                return
            }
            
            AppLogger.info("Interstitial ad loaded successfully", category: .general)
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
            AppLogger.debug("Premium user, skipping ad", category: .general)
            completion()
            return
        }
        
        guard adsEnabled else {
            AppLogger.debug("Ads disabled, skipping ad", category: .general)
            completion()
            return
        }
        
        guard let interstitialAd = interstitialAd else {
            AppLogger.debug("No ad available, loading new one", category: .general)
            SessionLogManager.shared.logAdError(adUnitId: adUnitID, error: "No ad available", context: "showInterstitialAd")
            loadInterstitialAd()
            completion()
            return
        }
        
        AppLogger.debug("Showing interstitial ad", category: .general)
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
            AppLogger.debug("Premium user - no ads", category: .general)
            return false
        }
        
        AppLogger.debug("shouldShowAd check: adsEnabled=\(adsEnabled), isAdReady=\(isAdReady), isSDKInitialized=\(isSDKInitialized)", category: .general)
        if !adsEnabled {
            AppLogger.debug("Ads are disabled in settings", category: .general)
            return false
        }
        if !isAdReady {
            AppLogger.debug("Ad not ready - will load in background for next time", category: .general)
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
    
    // MARK: - Rewarded Ad Methods
    
    /// Load a new rewarded video ad (for the "Watch 2 Videos" quest)
    func loadRewardedAd() {
        // Premium users don't need ads
        guard !PremiumManager.shared.isPremiumUser else { return }
        
        // Initialize SDK if not already done
        if !isSDKInitialized {
            initializeSDK()
            return
        }
        
        AppLogger.debug("Loading rewarded ad...", category: .general)
        
        RewardedAd.load(with: rewardedAdUnitID, request: Request()) { [weak self] ad, error in
            if let error = error {
                AppLogger.error("Failed to load rewarded ad: \(error.localizedDescription)", category: .general)
                SessionLogManager.shared.logAdLoad(success: false, adUnitId: self?.rewardedAdUnitID ?? "", loadTimeMs: 0, error: error.localizedDescription)
                DispatchQueue.main.async {
                    self?.isRewardedAdReady = false
                }
                return
            }
            
            AppLogger.info("Rewarded ad loaded successfully", category: .general)
            SessionLogManager.shared.logAdLoad(success: true, adUnitId: self?.rewardedAdUnitID ?? "", loadTimeMs: 0)
            self?.rewardedAd = ad
            self?.rewardedAd?.fullScreenContentDelegate = self
            
            DispatchQueue.main.async {
                self?.isRewardedAdReady = true
            }
        }
    }
    
    /// Show a rewarded video ad (for the daily quest)
    /// - Parameters:
    ///   - viewController: The view controller to present the ad from
    ///   - onReward: Called when the user earns the reward (watched full video)
    func showRewardedAd(from viewController: UIViewController, onReward: @escaping () -> Void) {
        // Premium users never see ads
        guard !PremiumManager.shared.isPremiumUser else {
            AppLogger.debug("Premium user, skipping rewarded ad", category: .general)
            return
        }
        
        guard let rewardedAd = rewardedAd else {
            AppLogger.debug("No rewarded ad available, loading new one", category: .general)
            SessionLogManager.shared.logAdError(adUnitId: rewardedAdUnitID, error: "No rewarded ad available", context: "showRewardedAd")
            loadRewardedAd()
            return
        }
        
        AppLogger.debug("Showing rewarded ad", category: .general)
        SessionLogManager.shared.logAdShow(adUnitId: rewardedAdUnitID, placement: "daily_quest_watch_ads")
        self.onRewardEarned = onReward
        self.isShowingRewardedAd = true
        self.adStartTime = Date()
        
        DispatchQueue.main.async {
            self.isShowingAd = true
            rewardedAd.present(from: viewController) { [weak self] in
                // User earned the reward (watched the full video)
                AppLogger.info("User earned rewarded ad reward!", category: .general)
                DispatchQueue.main.async {
                    self?.onRewardEarned?()
                    self?.onRewardEarned = nil
                }
            }
        }
    }
    
    /// Prepare a rewarded ad for the daily quest (call when ad quest is detected)
    func prepareRewardedAd() {
        // Premium users don't need ads
        guard !PremiumManager.shared.isPremiumUser else { return }
        
        if !isSDKInitialized {
            AppLogger.debug("Preparing rewarded ad, initializing SDK...", category: .general)
            initializeSDK()
            // After SDK init, loadRewardedAd will be called from the init callback
            // We need to also load rewarded when SDK finishes
        } else if !isRewardedAdReady {
            loadRewardedAd()
        }
    }
}

// MARK: - FullScreenContentDelegate

extension AdManager: FullScreenContentDelegate {
    
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        AppLogger.debug("Ad recorded impression", category: .general)
    }
    
    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        let unitId = isShowingRewardedAd ? rewardedAdUnitID : adUnitID
        AppLogger.debug("Ad recorded click", category: .general)
        SessionLogManager.shared.logAdClicked(adUnitId: unitId)
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let isRewarded = isShowingRewardedAd
        let unitId = isRewarded ? rewardedAdUnitID : adUnitID
        AppLogger.error("\(isRewarded ? "Rewarded" : "Interstitial") ad failed to present: \(error.localizedDescription)", category: .general)
        SessionLogManager.shared.logAdError(adUnitId: unitId, error: error.localizedDescription, context: "present")
        DispatchQueue.main.async {
            self.isShowingAd = false
            if isRewarded {
                self.isRewardedAdReady = false
                self.isShowingRewardedAd = false
                self.onRewardEarned = nil
            } else {
                self.isAdReady = false
                self.onAdDismissed?()
                self.onAdDismissed = nil
            }
        }
        // Try to load a new ad
        if isRewarded {
            loadRewardedAd()
        } else {
            loadInterstitialAd()
        }
    }
    
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        AppLogger.debug("Ad will present", category: .general)
    }
    
    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        AppLogger.debug("Ad will dismiss", category: .general)
    }
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let isRewarded = isShowingRewardedAd
        let unitId = isRewarded ? rewardedAdUnitID : adUnitID
        AppLogger.debug("\(isRewarded ? "Rewarded" : "Interstitial") ad dismissed", category: .general)
        
        // Calculate how long the ad was shown and ROUND to whole seconds
        let rawDuration = Date().timeIntervalSince(adStartTime ?? Date())
        let roundedDuration = round(rawDuration)
        AppLogger.debug("Ad was shown for \(rawDuration)s (raw) → \(roundedDuration)s (rounded)", category: .general)
        
        // Log the ad dismissal with watch duration
        SessionLogManager.shared.logAdDismissed(adUnitId: unitId, watchedDurationMs: Int(rawDuration * 1000))
        
        if isRewarded {
            // Rewarded ad dismissed — reward was already granted in the present() callback
            DispatchQueue.main.async {
                self.isShowingAd = false
                self.isRewardedAdReady = false
                self.isShowingRewardedAd = false
                self.onRewardEarned = nil
                AppLogger.debug("Rewarded ad fully dismissed", category: .general)
            }
            // Preload the next rewarded ad
            loadRewardedAd()
        } else {
            // Store the ROUNDED ad duration for the rest timer calculation
            lastAdDuration = roundedDuration
            
            // IMMEDIATELY call completion - don't wait for minimum duration
            // The rest timer will account for the actual ad time shown
            DispatchQueue.main.async {
                self.isShowingAd = false
                self.isAdReady = false
                AppLogger.debug("Calling ad completion callback...", category: .general)
                self.onAdDismissed?()
                self.onAdDismissed = nil
                AppLogger.debug("Ad completion callback finished", category: .general)
            }
            // Preload the next interstitial ad
            loadInterstitialAd()
        }
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
