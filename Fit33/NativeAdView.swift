import SwiftUI
import GoogleMobileAds

// MARK: - Native Ad Card for Received Workouts
/// A native ad that blends seamlessly with workout cards

struct NativeAdCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var adLoader = NativeAdLoader()
    @StateObject private var premiumManager = PremiumManager.shared
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        Group {
            // Only show ads for free users
            if !premiumManager.isPremiumUser {
                if let nativeAd = adLoader.nativeAd {
                    // Native ad loaded - show custom layout
                    NativeAdContentView(nativeAd: nativeAd, cardBackground: cardBackground)
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

// MARK: - Native Ad Content (Custom Layout)
struct NativeAdContentView: View {
    let nativeAd: NativeAd
    let cardBackground: Color
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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Fallback icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 18))
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
                        .padding(.horizontal, 8)
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
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Loading Ad Card
struct LoadingAdCard: View {
    let cardBackground: Color
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Placeholder icon
                RoundedRectangle(cornerRadius: 8)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
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
            print("📺 [NATIVE] Ads disabled, not loading")
            return
        }
        
        // Ensure SDK is initialized before loading ads
        AdManager.shared.initializeSDK()
        
        guard let rootVC = RootViewControllerFinder.find() else {
            print("📺 [NATIVE] No root view controller found")
            return
        }
        
        print("📺 [NATIVE] Loading native ad...")
        
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
        print("📺 [NATIVE] Native ad loaded successfully")
        DispatchQueue.main.async {
            self.nativeAd = nativeAd
        }
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("📺 [NATIVE] Failed to load native ad: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.nativeAd = nil
        }
    }
    
    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        print("📺 [NATIVE] Ad loader finished")
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
                            .font(.system(size: 16))
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
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // CTA button
            if let callToAction = nativeAd.callToAction {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Text(callToAction)
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
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
        print("📢 [Banner] makeUIView called")
        
        // Ensure SDK is initialized before loading ads
        AdManager.shared.initializeSDK()
        print("📢 [Banner] SDK initialization requested")
        
        let bannerView = BannerView()
        
        // CRITICAL: Set frame AND ad size BEFORE setting ad unit ID
        // Use full screen width for adaptive banner
        let screenWidth = UIScreen.main.bounds.width
        bannerView.frame = CGRect(x: 0, y: 0, width: screenWidth, height: 50)
        
        // Use adaptive banner size matching screen width  
        bannerView.adSize = portraitAnchoredAdaptiveBanner(width: screenWidth)
        print("📢 [Banner] Set frame: \(bannerView.frame) and adaptive banner for width: \(screenWidth)")
        
        // Use test ad unit ID in debug, production ID in release
        #if DEBUG
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716" // Google test banner
        print("📢 [Banner] Using TEST ad unit ID")
        #else
        bannerView.adUnitID = "ca-app-pub-8809892203317185/7456758464" // Production banner
        print("📢 [Banner] Using PRODUCTION ad unit ID")
        #endif
        
        // Set the root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootViewController
            print("📢 [Banner] Root view controller set")
        } else {
            print("⚠️ [Banner] Could not find root view controller")
        }
        
        // Set delegate
        bannerView.delegate = context.coordinator
        print("📢 [Banner] Delegate set")
        
        // Load the ad
        let request = Request()
        bannerView.load(request)
        print("📢 [Banner] Ad load requested with size: \(bannerView.adSize.size)")
        
        // Mark that we've attempted to load
        DispatchQueue.main.async {
            self.bannerState.hasAttemptedLoad = true
            print("📢 [Banner] hasAttemptedLoad set to true")
        }
        
        return bannerView
    }
    
    func updateUIView(_ bannerView: BannerView, context: Context) {
        // Update frame if screen width changed (rotation)
        let screenWidth = UIScreen.main.bounds.width
        if bannerView.frame.width != screenWidth {
            bannerView.frame = CGRect(x: 0, y: 0, width: screenWidth, height: 50)
            bannerView.adSize = portraitAnchoredAdaptiveBanner(width: screenWidth)
            print("📢 [Banner] Updated frame and size for new width: \(screenWidth)")
        }
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, BannerViewDelegate {
        let bannerState: BannerAdState
        
        init(bannerState: BannerAdState) {
            self.bannerState = bannerState
        }
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("📢 [Banner] ✅ Banner ad loaded successfully!")
            DispatchQueue.main.async {
                self.bannerState.isAdLoaded = true
                print("📢 [Banner] bannerState.isAdLoaded set to TRUE")
            }
        }
        
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("❌ [Banner] Banner ad failed to load: \(error.localizedDescription)")
            print("❌ [Banner] Error code: \((error as NSError).code)")
            DispatchQueue.main.async {
                self.bannerState.isAdLoaded = false
            }
        }
        
        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            print("👁️ [Banner] Banner ad impression recorded")
        }
        
        func bannerViewDidRecordClick(_ bannerView: BannerView) {
            print("👆 [Banner] Banner ad clicked")
        }
    }
}
