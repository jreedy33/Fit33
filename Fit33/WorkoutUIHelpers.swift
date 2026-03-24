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

// MARK: - Marquee Text Component (TimelineView-based, no CADisplayLink)

struct MarqueeText: View {
    let text: String
    let font: Font
    let weight: Font.Weight
    let shouldAnimate: Bool

    private let speed: CGFloat = 40
    private let gap: CGFloat = 60
    private let pauseSec: Double = 1.8
    private let easeSec: Double = 0.35

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animationStart: Date?

    private var needsScrolling: Bool { textWidth > containerWidth - 10 }
    private var cycle: CGFloat { textWidth + gap }

    init(text: String, font: Font = .headline, weight: Font.Weight = .semibold, shouldAnimate: Bool = true) {
        self.text = text
        self.font = font
        self.weight = weight
        self.shouldAnimate = shouldAnimate
    }

    var body: some View {
        let running = shouldAnimate && needsScrolling && animationStart != nil
        TimelineView(.animation(paused: !running)) { timeline in
            GeometryReader { geo in
                let cw = geo.size.width
                let xOff = running ? offset(at: timeline.date) : 0
                HStack(spacing: gap) {
                    label
                        .background(GeometryReader { tg in
                            Color.clear.onAppear {
                                textWidth = tg.size.width
                                containerWidth = cw
                            }
                        })
                    if needsScrolling { label }
                }
                .offset(x: xOff)
                .frame(width: cw, alignment: .leading)
                .clipped()
            }
        }
        .frame(height: 22)
        .clipped()
        .onChange(of: shouldAnimate) { _, on in
            animationStart = (on && needsScrolling) ? Date() : nil
        }
        .onChange(of: textWidth) { old, new in
            guard abs(old - new) >= 1 else { return }
            animationStart = (shouldAnimate && needsScrolling) ? Date() : nil
        }
        .onDisappear { animationStart = nil }
    }

    private func offset(at date: Date) -> CGFloat {
        guard let start = animationStart, cycle > 0 else { return 0 }
        let easeDistance = speed * CGFloat(easeSec) * 0.5
        let cruiseDist = cycle - easeDistance
        let cruiseSec = Double(cruiseDist / speed)
        let total = pauseSec + easeSec + cruiseSec

        let pos = date.timeIntervalSince(start).truncatingRemainder(dividingBy: total)
        if pos < pauseSec { return 0 }

        let t1 = pos - pauseSec
        if t1 < easeSec {
            let p = t1 / easeSec
            let e = p * p * (3.0 - 2.0 * p)
            return -speed * CGFloat(easeSec) * CGFloat(e) * 0.5
        }

        let t2 = t1 - easeSec
        return -(easeDistance + speed * CGFloat(t2))
    }

    private var label: some View {
        Text(text).font(font).fontWeight(weight).fixedSize()
    }
}
