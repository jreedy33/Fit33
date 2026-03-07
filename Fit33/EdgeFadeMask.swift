import SwiftUI
import UIKit
import AVFoundation

// MARK: - Edge Fade Style

/// Controls the shape of the geometric edge-fade mask
enum EdgeFadeStyle {
    /// Elliptical feather that fades all edges equally — best for exercise loop videos
    case radial
    /// Feathers top and bottom edges only — good for horizontal banners
    case vertical
}

// MARK: - SwiftUI Edge Fade ViewModifier (Geometric)

/// Applies a soft geometric alpha-mask to any SwiftUI view so its edges
/// fade to transparent. Use on exercise loop videos so the rectangular
/// boundary dissolves into the gradient behind it.
///
/// ⚠️ Geometric masks can clip exercise figures that extend near the edges.
/// For content-aware blending that never clips the figure, use
/// `.seamlessVideoEmbed()` instead — it combines this mask with
/// `.blendMode(.multiply)` to remove white based on pixel color.
struct EdgeFadeMask: ViewModifier {
    var style: EdgeFadeStyle = .radial
    /// 0.0 = no fade, 0.25 = noticeable, 0.4 = very soft
    var feather: CGFloat = 0.18
    /// Higher = smoother gradient transition (adds blur to mask)
    var softness: CGFloat = 0.35

    func body(content: Content) -> some View {
        content.mask(maskView)
    }

    @ViewBuilder
    private var maskView: some View {
        GeometryReader { geo in
            switch style {
            case .radial:
                // Elliptical mask that fits the view bounds.
                // End radius = half the diagonal so the gradient reaches corners.
                let diagonal = hypot(geo.size.width, geo.size.height) / 2
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: max(0.0, 1.0 - feather - softness * 0.1)),
                        .init(color: .clear, location: 1.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: diagonal
                )
                .scaleEffect(x: geo.size.width / max(diagonal * 2, 1),
                              y: geo.size.height / max(diagonal * 2, 1))
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: softness * 18)

            case .vertical:
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: feather),
                        .init(color: .black, location: 1.0 - feather),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: softness * 12)
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a geometric edge-fade alpha mask so the view's edges dissolve to transparent.
    ///
    /// - Parameters:
    ///   - style: `.radial` for elliptical feather, `.vertical` for top/bottom only.
    ///   - feather: How much of the edge fades (0.0–0.4). Default 0.18.
    ///   - softness: Extra blur on the gradient mask (0.0–1.0). Default 0.35.
    func edgeFadeMask(
        style: EdgeFadeStyle = .radial,
        feather: CGFloat = 0.18,
        softness: CGFloat = 0.35
    ) -> some View {
        modifier(EdgeFadeMask(style: style, feather: feather, softness: softness))
    }

    /// **Content-aware** seamless video embed for white-background exercise videos.
    ///
    /// This is the recommended modifier for exercise loop videos. It combines two
    /// techniques so the exercise figure is **never clipped**, regardless of where
    /// the animation moves within the frame:
    ///
    /// 1. **`.blendMode(.multiply)`** — Makes white pixels become the background
    ///    color. Dark pixels (the exercise figure) stay fully visible. This is
    ///    color-based, not position-based, so it adapts automatically to every video.
    ///
    /// 2. **Soft geometric edge fade** — Dissolves the rectangular video boundary
    ///    so there's no hard frame edge. Uses gentle settings that won't clip content.
    ///
    /// The result: the white rectangle disappears, the figure floats on the gradient
    /// background, and the edges feather smoothly — premium "seamless embed" look.
    ///
    /// - Parameters:
    ///   - feather: Geometric edge fade amount (0.0–0.4). Default 0.15 (gentle).
    ///   - softness: Geometric edge blur (0.0–1.0). Default 0.45 (smooth).
    ///   - fadeStyle: `.radial` or `.vertical`. Default `.radial`.
    func seamlessVideoEmbed(
        feather: CGFloat = 0.15,
        softness: CGFloat = 0.45,
        fadeStyle: EdgeFadeStyle = .radial
    ) -> some View {
        self
            // Step 1: Flatten the view into a single compositing layer
            .compositingGroup()
            // Step 2: Multiply blend — white (1,1,1) × background = background
            //         Figure pixels × background = slightly tinted figure (looks integrated)
            .blendMode(.multiply)
            // Step 3: Gentle geometric fade at the rectangular boundary for polish
            .edgeFadeMask(style: fadeStyle, feather: feather, softness: softness)
    }
}

// MARK: - UIKit CALayer Mask for AVPlayerLayer

/// A UIView that wraps an AVPlayerLayer and applies a CAGradientLayer mask
/// so the video edges fade to transparent. Works with AVQueuePlayer + AVPlayerLooper.
///
/// The mask is created once and updated on layout changes only — no per-frame cost.
///
/// Usage (UIKit):
/// ```
/// let maskedView = EdgeFadedPlayerView(player: queuePlayer, style: .radial)
/// containerView.addSubview(maskedView)
/// ```
class EdgeFadedPlayerView: UIView {

    // MARK: - Properties

    let playerLayer: AVPlayerLayer
    private let maskLayer = CAGradientLayer()
    private var fadeStyle: EdgeFadeStyle
    private var feather: CGFloat
    private var softness: CGFloat

    // MARK: - Init

    /// - Parameters:
    ///   - player: The AVPlayer (typically AVQueuePlayer with AVPlayerLooper).
    ///   - style: `.radial` or `.vertical` fade shape.
    ///   - feather: 0.0–0.4, how much of the edges fade. Default 0.18.
    ///   - softness: 0.0–1.0, controls how smooth the gradient is. Default 0.35.
    init(
        player: AVPlayer,
        style: EdgeFadeStyle = .radial,
        feather: CGFloat = 0.18,
        softness: CGFloat = 0.35
    ) {
        self.playerLayer = AVPlayerLayer(player: player)
        self.fadeStyle = style
        self.feather = feather
        self.softness = softness

        super.init(frame: .zero)

        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.clear.cgColor
        layer.addSublayer(playerLayer)

        configureMask()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update frames without animation to avoid flicker
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        maskLayer.frame = bounds
        updateMaskShape()
        CATransaction.commit()
    }

    // MARK: - Mask Configuration

    private func configureMask() {
        layer.mask = maskLayer
        updateMaskShape()
    }

    /// Reconfigure mask parameters dynamically
    func updateConfiguration(style: EdgeFadeStyle, feather: CGFloat, softness: CGFloat) {
        self.fadeStyle = style
        self.feather = feather
        self.softness = softness
        updateMaskShape()
    }

    private func updateMaskShape() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch fadeStyle {
        case .radial:
            maskLayer.type = .radial
            maskLayer.startPoint = CGPoint(x: 0.5, y: 0.5) // center
            maskLayer.endPoint = CGPoint(x: 1.0, y: 1.0)   // corner

            let innerStop = max(0.0, 1.0 - feather - softness * 0.1)
            maskLayer.colors = [
                UIColor.black.cgColor,
                UIColor.black.cgColor,
                UIColor.clear.cgColor
            ]
            maskLayer.locations = [
                0.0 as NSNumber,
                NSNumber(value: Double(innerStop)),
                1.0 as NSNumber
            ]

        case .vertical:
            maskLayer.type = .axial
            maskLayer.startPoint = CGPoint(x: 0.5, y: 0.0) // top
            maskLayer.endPoint = CGPoint(x: 0.5, y: 1.0)   // bottom

            maskLayer.colors = [
                UIColor.clear.cgColor,
                UIColor.black.cgColor,
                UIColor.black.cgColor,
                UIColor.clear.cgColor
            ]
            maskLayer.locations = [
                0.0 as NSNumber,
                NSNumber(value: Double(feather)),
                NSNumber(value: Double(1.0 - feather)),
                1.0 as NSNumber
            ]
        }

        CATransaction.commit()
    }
}

// MARK: - SwiftUI Wrapper for EdgeFadedPlayerView

/// SwiftUI UIViewRepresentable that wraps EdgeFadedPlayerView.
/// Use this instead of `VideoPlayerLayerView` when you want the UIKit-based
/// edge-fade effect (e.g., in non-SwiftUI screens).
struct EdgeFadedVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    var style: EdgeFadeStyle = .radial
    var feather: CGFloat = 0.18
    var softness: CGFloat = 0.35

    func makeUIView(context: Context) -> EdgeFadedPlayerView {
        EdgeFadedPlayerView(
            player: player,
            style: style,
            feather: feather,
            softness: softness
        )
    }

    func updateUIView(_ uiView: EdgeFadedPlayerView, context: Context) {
        uiView.updateConfiguration(style: style, feather: feather, softness: softness)
    }
}

// MARK: - Demo View

/// Demo view showing a looping exercise video with gradient background
/// and the content-aware seamless embed applied.
struct EdgeFadeMaskDemoView: View {
    let exerciseName: String
    let categoryColor: Color
    var videoFilename: String? = nil

    var body: some View {
        ZStack {
            // Gradient background (similar to app theme)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.78, green: 0.91, blue: 0.99),
                    Color(red: 0.67, green: 0.88, blue: 0.93),
                    Color(red: 0.60, green: 0.85, blue: 0.95)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Seamless Video Embed")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Video with content-aware seamless embed
                RemoteVideoPlayerView(
                    exerciseName: exerciseName,
                    categoryColor: categoryColor,
                    videoFilename: videoFilename,
                    seamlessBlend: true
                )
                .seamlessVideoEmbed(feather: 0.15, softness: 0.45)
                .frame(maxWidth: 520)
                .padding(.horizontal, Spacing.md)

                VStack(spacing: 8) {
                    Text("Content-Aware Blend + Edge Fade")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    Text("multiply blend removes white · figure never clipped")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
            }
            .padding(.top, 60)
        }
    }
}
