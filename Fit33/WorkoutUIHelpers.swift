import SwiftUI

// MARK: - Custom Shapes

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Marquee Text Component (TimelineView, frame-driven)
//
// Implementation notes (consulted DESIGN_AGENT animation table + QUALITY_PERFORMANCE
// invariants 13/14 + swiftui-rules invariant 4):
//
// Why this (final) version uses TimelineView:
//   Earlier rewrites used a `Task` loop driving `withAnimation(.linear)` on a
//   `@State phase`. That works ONLY if the surrounding view tree allows
//   internal animations to propagate. ExerciseCard previously had a blanket
//   `.transaction { transaction.animation = .easeInOut(duration: 0.2) }`
//   modifier that was overriding our linear scroll, producing flicker. Even
//   after fixing that, ANY parent that sets a custom transaction (selection
//   highlight animations, drag gestures, etc.) can still poison the marquee.
//   The only way to be bulletproof is to not depend on the SwiftUI animation
//   system at all: `TimelineView(.animation)` ticks at display refresh rate
//   and we compute the exact offset from elapsed time on every frame. No
//   `withAnimation`, no transactions, no restart races.
//
// Visual contract (still the same):
//   - Two labels rendered side-by-side, separated by `gap`.
//   - Each cycle: hold at offset 0 for `pauseSec`, then linearly slide left
//     over `cycle/speed` seconds until the second label sits exactly where
//     the first label started (offset = -cycle = -(textWidth + gap)).
//   - At that exact moment the cycle wraps back to 0. Visually identical
//     because the second label's previous position == the first label's
//     new position == pixel-perfect seamless wrap.
//
// Motion gating: respects `isLowPowerMode` AND `accessibilityReduceMotion`
// per QUALITY_PERFORMANCE_AGENT invariant 13. When disabled, TimelineView
// is paused and offset stays at 0.

private struct MarqueeTextSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    let weight: Font.Weight
    let shouldAnimate: Bool

    /// Linear scroll speed in points/sec. ~24pt/s reads as a measured ticker
    /// — slow enough to look deliberate, fast enough to not feel stuck.
    private let speed: CGFloat = 24
    /// Empty space between the duplicated labels. ~48pt reads as breathing
    /// space without making the text look like it lapped itself.
    private let gap: CGFloat = 48
    /// Hold at offset = 0 before each scroll. Long enough to read the start.
    private let pauseSec: Double = 1.6

    @State private var textSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    /// Anchor time the loop measures elapsed seconds against. Reset whenever
    /// `text` or `shouldAnimate` changes so the new cycle starts cleanly at
    /// offset 0 with a full pause.
    @State private var startDate: Date = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(text: String, font: Font = .headline, weight: Font.Weight = .semibold, shouldAnimate: Bool = true) {
        self.text = text
        self.font = font
        self.weight = weight
        self.shouldAnimate = shouldAnimate
    }

    private var disableMotion: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || reduceMotion
    }

    private var needsScrolling: Bool {
        guard containerWidth > 0 else { return false }
        return textSize.width > containerWidth + 1
    }

    private var isAnimating: Bool {
        shouldAnimate && !disableMotion && needsScrolling && textSize.width > 0
    }

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            GeometryReader { geo in
                HStack(spacing: gap) {
                    label
                    label
                        .opacity(needsScrolling ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .fixedSize()
                .offset(x: offset(at: context.date))
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .clipped()
                .onAppear {
                    if abs(containerWidth - geo.size.width) > 0.5 {
                        containerWidth = geo.size.width
                    }
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    guard abs(containerWidth - newWidth) > 0.5 else { return }
                    containerWidth = newWidth
                }
            }
        }
        .frame(height: max(textSize.height, 22))
        .background(measurement)
        .onPreferenceChange(MarqueeTextSizeKey.self) { newSize in
            guard newSize != textSize else { return }
            textSize = newSize
            startDate = Date()
        }
        .onChange(of: shouldAnimate) { _, on in
            if on { startDate = Date() }
        }
        .onChange(of: text) { _, _ in
            startDate = Date()
        }
    }

    private var measurement: some View {
        label
            .hidden()
            .fixedSize()
            .background(
                GeometryReader { mg in
                    Color.clear.preference(key: MarqueeTextSizeKey.self, value: mg.size)
                }
            )
    }

    private var label: some View {
        Text(text)
            .font(font)
            .fontWeight(weight)
            .fixedSize()
            .lineLimit(1)
    }

    /// Pure function: given the current TimelineView tick date, return the
    /// horizontal offset to apply. Constant-velocity linear motion with a
    /// pause at the start of each cycle. No animation, no state.
    private func offset(at date: Date) -> CGFloat {
        guard isAnimating else { return 0 }
        let cycle = textSize.width + gap
        guard cycle > 0 else { return 0 }
        let scrollSec = Double(cycle / speed)
        let totalSec = pauseSec + scrollSec
        let elapsed = max(0, date.timeIntervalSince(startDate))
        let phase = elapsed.truncatingRemainder(dividingBy: totalSec)
        if phase < pauseSec { return 0 }
        let scrolled = (phase - pauseSec) / scrollSec  // 0..1, linear
        return -CGFloat(scrolled) * cycle
    }
}
