import SwiftUI
import GoogleMobileAds

// MARK: - Native Ad Card for Received Workouts
/// A native ad that blends seamlessly with workout cards

struct NativeAdCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var adLoader = NativeAdLoader()
    @StateObject private var premiumManager = PremiumManager.shared
    @State private var showRemoveAdsPaywall = false

    var body: some View {
        Group {
            // Only show ads for free users
            if !premiumManager.isPremiumUser {
                if let nativeAd = adLoader.nativeAd {
                    // Native ad with always-visible "Remove Ads" button —
                    // turns every ad impression into a Pro upsell impression
                    // (Phase 1 cheat-code, 2026-05-03 monetization sweep).
                    ZStack(alignment: .topTrailing) {
                        NativeAdContentView(nativeAd: nativeAd)

                        Button {
                            HapticManager.impact(.light)
                            showRemoveAdsPaywall = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .heavy))
                                Text("Remove")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                        .padding(.trailing, 10)
                        .accessibilityLabel("Remove ads")
                        .accessibilityHint("Open Pro upgrade to remove all ads")
                    }
                }
                // If no ad loaded, show nothing (no grey placeholder)
            }
        }
        .onAppear {
            // Only load ads for free users
            if !premiumManager.isPremiumUser {
                adLoader.loadAd()
            }
        }
        .fullScreenCover(isPresented: $showRemoveAdsPaywall) {
            PremiumUpgradeView(triggeringFeature: .removeAds)
        }
    }
}

// MARK: - Native Ad Content (Custom Layout)
struct NativeAdContentView: View {
    let nativeAd: NativeAd
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and "Sponsored" badge
            HStack(spacing: 12) {
                // App icon or brand image
                if let iconImage = nativeAd.icon?.image {
                    Image(uiImage: iconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                } else {
                    // Fallback icon
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "megaphone.fill")
                            .font(.ds_heading3)
                            .foregroundColor(.orange)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(nativeAd.headline ?? "Advertisement")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // Sponsored badge
                    Text("Sponsored")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )
                }
                
                Spacer()
            }
            
            // Description
            if let body = nativeAd.body {
                Text(body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            // Call to action button
            if let callToAction = nativeAd.callToAction {
                Button(action: {
                    // The tap is handled by the native ad view wrapper
                }) {
                    HStack {
                        Text(callToAction)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.ds_caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
            }
            
            // "Ad" indicator (required by Google)
            HStack {
                Text("Ad")
                    .font(.system(size: 9))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray)
                    )
                
                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Loading Ad Card
struct LoadingAdCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Placeholder icon
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 8)
                }
                
                Spacer()
            }
            
            // Description placeholder
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 10)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Native Ad Loader
class NativeAdLoader: NSObject, ObservableObject, NativeAdLoaderDelegate {
    @Published var nativeAd: NativeAd?
    private var adLoader: AdLoader?
    
    // Native Ad Unit ID
    #if DEBUG
    private let adUnitID = "ca-app-pub-3940256099942544/3986624511" // Google test native ad
    #else
    private let adUnitID = "ca-app-pub-8809892203317185/7484678627" // Production native ad
    #endif
    
    func loadAd() {
        guard AdManager.shared.adsEnabled else {
            AppLogger.debug("📺 [NATIVE] Ads disabled, not loading", category: .ui)
            return
        }
        
        // Ensure SDK is initialized before loading ads
        AdManager.shared.initializeSDK()
        
        guard let rootVC = RootViewControllerFinder.find() else {
            AppLogger.debug("📺 [NATIVE] No root view controller found", category: .ui)
            return
        }
        
        AppLogger.debug("📺 [NATIVE] Loading native ad...", category: .ui)
        
        let options = NativeAdViewAdOptions()
        options.preferredAdChoicesPosition = .topRightCorner
        
        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [options]
        )
        adLoader?.delegate = self
        adLoader?.load(Request())
    }
    
    // MARK: - GADNativeAdLoaderDelegate
    
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        AppLogger.debug("📺 [NATIVE] Native ad loaded successfully", category: .ui)
        DispatchQueue.main.async {
            self.nativeAd = nativeAd
        }
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        AppLogger.error("📺 [NATIVE] Failed to load native ad: \(error.localizedDescription)", category: .ui)
        DispatchQueue.main.async {
            self.nativeAd = nil
        }
    }
    
    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        AppLogger.debug("📺 [NATIVE] Ad loader finished", category: .ui)
    }
}

// MARK: - Workout Native Ad Card (for Active Workout)
/// Native ad card styled for the active workout view
/// Only shows content when an ad has loaded - no placeholder/skeleton
struct WorkoutNativeAdCard: View {
    @StateObject private var adLoader = NativeAdLoader()
    @StateObject private var premiumManager = PremiumManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Group {
            // Only show ads for free users
            if !premiumManager.isPremiumUser {
                if let nativeAd = adLoader.nativeAd {
                    // Native ad loaded - show it
                    WorkoutNativeAdContent(nativeAd: nativeAd)
                }
                // If no ad loaded, show nothing (no grey placeholder)
            }
        }
        .onAppear {
            // Only load ads for free users
            if !premiumManager.isPremiumUser {
                adLoader.loadAd()
            }
        }
    }
}

// MARK: - Workout Native Ad Content
struct WorkoutNativeAdContent: View {
    let nativeAd: NativeAd
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // App icon
                if let iconImage = nativeAd.icon?.image {
                    Image(uiImage: iconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "megaphone.fill")
                            .font(.ds_bodyRegular)
                            .foregroundColor(.orange)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(nativeAd.headline ?? "Advertisement")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("Sponsored")
                        .font(.system(size: 9))
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
                
                Spacer()
                
                // "Ad" badge (required)
                Text("Ad")
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.gray))
            }
            
            // Description (if available)
            if let body = nativeAd.body {
                Text(body)
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // CTA button
            if let callToAction = nativeAd.callToAction {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Text(callToAction)
                            .font(.ds_caption)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Workout Ad Loading Card
struct WorkoutAdLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 60, height: 8)
                }
                
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - UIKit Wrapper for Native Ad (if needed for more advanced layouts)
/// This can be used if you need more control over the native ad view
struct NativeAdUIKitWrapper: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> NativeAdView {
        let adView = Bundle.main.loadNibNamed("NativeAdView", owner: nil, options: nil)?.first as? NativeAdView ?? NativeAdView()
        return adView
    }
    
    func updateUIView(_ adView: NativeAdView, context: Context) {
        adView.nativeAd = nativeAd
        
        // Map the ad assets to views
        (adView.headlineView as? UILabel)?.text = nativeAd.headline
        (adView.bodyView as? UILabel)?.text = nativeAd.body
        (adView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        (adView.iconView as? UIImageView)?.image = nativeAd.icon?.image
        (adView.advertiserView as? UILabel)?.text = nativeAd.advertiser
        
        // Hide unused components
        adView.callToActionView?.isHidden = nativeAd.callToAction == nil
        adView.iconView?.isHidden = nativeAd.icon == nil
    }
}

// MARK: - Banner Ad View
/// A standard banner ad that sits at the bottom of the screen
/// Only shows content when an ad has actually loaded
struct BannerAdView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var bannerState = BannerAdState()
    @StateObject private var premiumManager = PremiumManager.shared
    
    var body: some View {
        // Only show for free users with ads enabled
        let shouldShow = !premiumManager.isPremiumUser && AdManager.shared.adsEnabled
        
        if shouldShow {
            BannerAdRepresentable(bannerState: bannerState)
                .frame(height: 50)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Banner Ad State
/// Tracks whether a banner ad has loaded successfully
class BannerAdState: ObservableObject {
    @Published var isAdLoaded = false
    @Published var hasAttemptedLoad = false
}

// MARK: - Banner Ad UIKit Wrapper
struct BannerAdRepresentable: UIViewRepresentable {
    @ObservedObject var bannerState: BannerAdState
    
    func makeCoordinator() -> Coordinator {
        Coordinator(bannerState: bannerState)
    }
    
    func makeUIView(context: Context) -> BannerView {
        AppLogger.debug("📢 [Banner] makeUIView called", category: .ui)
        
        // Ensure SDK is initialized before loading ads
        AdManager.shared.initializeSDK()
        AppLogger.debug("📢 [Banner] SDK initialization requested", category: .ui)
        
        let bannerView = BannerView()
        
        // CRITICAL: Set frame AND ad size BEFORE setting ad unit ID
        // Use full screen width for adaptive banner
        let screenWidth = UIScreen.main.bounds.width
        bannerView.frame = CGRect(x: 0, y: 0, width: screenWidth, height: 50)
        
        // Use adaptive banner size matching screen width  
        bannerView.adSize = portraitAnchoredAdaptiveBanner(width: screenWidth)
        AppLogger.debug("📢 [Banner] Set frame: \(bannerView.frame) and adaptive banner for width: \(screenWidth)", category: .ui)
        
        // Use test ad unit ID in debug, production ID in release
        #if DEBUG
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716" // Google test banner
        AppLogger.debug("📢 [Banner] Using TEST ad unit ID", category: .ui)
        #else
        bannerView.adUnitID = "ca-app-pub-8809892203317185/7456758464" // Production banner
        AppLogger.debug("📢 [Banner] Using PRODUCTION ad unit ID", category: .ui)
        #endif
        
        // Set the root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootViewController
            AppLogger.debug("📢 [Banner] Root view controller set", category: .ui)
        } else {
            AppLogger.warning("⚠️ [Banner] Could not find root view controller", category: .ui)
        }
        
        // Set delegate
        bannerView.delegate = context.coordinator
        AppLogger.debug("📢 [Banner] Delegate set", category: .ui)
        
        // Load the ad
        let request = Request()
        bannerView.load(request)
        AppLogger.debug("📢 [Banner] Ad load requested with size: \(bannerView.adSize.size)", category: .ui)
        
        // Mark that we've attempted to load
        DispatchQueue.main.async {
            self.bannerState.hasAttemptedLoad = true
            AppLogger.debug("📢 [Banner] hasAttemptedLoad set to true", category: .ui)
        }
        
        return bannerView
    }
    
    func updateUIView(_ bannerView: BannerView, context: Context) {
        // Update frame if screen width changed (rotation)
        let screenWidth = UIScreen.main.bounds.width
        if bannerView.frame.width != screenWidth {
            bannerView.frame = CGRect(x: 0, y: 0, width: screenWidth, height: 50)
            bannerView.adSize = portraitAnchoredAdaptiveBanner(width: screenWidth)
            AppLogger.debug("📢 [Banner] Updated frame and size for new width: \(screenWidth)", category: .ui)
        }
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, BannerViewDelegate {
        let bannerState: BannerAdState
        
        init(bannerState: BannerAdState) {
            self.bannerState = bannerState
        }
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AppLogger.info("📢 [Banner] ✅ Banner ad loaded successfully!", category: .ui)
            DispatchQueue.main.async {
                self.bannerState.isAdLoaded = true
                AppLogger.debug("📢 [Banner] bannerState.isAdLoaded set to TRUE", category: .ui)
            }
        }
        
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            AppLogger.error("❌ [Banner] Banner ad failed to load: \(error.localizedDescription)", category: .ui)
            AppLogger.error("❌ [Banner] Error code: \((error as NSError).code)", category: .ui)
            DispatchQueue.main.async {
                self.bannerState.isAdLoaded = false
            }
        }
        
        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            AppLogger.debug("👁️ [Banner] Banner ad impression recorded", category: .ui)
        }
        
        func bannerViewDidRecordClick(_ bannerView: BannerView) {
            AppLogger.debug("👆 [Banner] Banner ad clicked", category: .ui)
        }
    }
}
