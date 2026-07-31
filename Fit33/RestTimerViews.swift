import SwiftUI

struct RestTimerIndicator: View {
    @ObservedObject var restTimer: RestTimer
    
    var body: some View {
        HStack(spacing: 12) {
            // Progress bar
            VStack(spacing: 4) {
                HStack {
                    Text("Rest")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Text(formatTime(restTimer.timeRemaining))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                ProgressView(value: 1 - (restTimer.timeRemaining / restTimer.totalTime))
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
            }
            
            // Control buttons
            HStack(spacing: 8) {
                Button(action: {
                    if restTimer.isActive {
                        restTimer.pause()
                    } else {
                        restTimer.resume()
                    }
                }) {
                    Image(systemName: restTimer.isActive ? "pause.fill" : "play.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .frame(width: 20, height: 20)
                }
                
                Button(action: {
                    restTimer.stop()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(CornerRadius.sm)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct TimerBorderShape: InsettableShape {
    let cornerRadius: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> TimerBorderShape {
        TimerBorderShape(cornerRadius: cornerRadius, inset: inset + amount)
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let cr = min(cornerRadius - inset, min(r.width, r.height) / 2)
        let k: CGFloat = 0.62 * cr

        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))

        p.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + cr),
                    control1: CGPoint(x: r.maxX - cr + k, y: r.minY),
                    control2: CGPoint(x: r.maxX, y: r.minY + cr - k))

        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cr))
        p.addCurve(to: CGPoint(x: r.maxX - cr, y: r.maxY),
                    control1: CGPoint(x: r.maxX, y: r.maxY - cr + k),
                    control2: CGPoint(x: r.maxX - cr + k, y: r.maxY))

        p.addLine(to: CGPoint(x: r.minX + cr, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - cr),
                    control1: CGPoint(x: r.minX + cr - k, y: r.maxY),
                    control2: CGPoint(x: r.minX, y: r.maxY - cr + k))

        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cr))
        p.addCurve(to: CGPoint(x: r.minX + cr, y: r.minY),
                    control1: CGPoint(x: r.minX, y: r.minY + cr - k),
                    control2: CGPoint(x: r.minX + cr - k, y: r.minY))

        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        return p
    }
}

// Q2-82 (Sprint 8): @MainActor isolation. All writes already happen on main
// (CADisplayLink fires on `.main`, foreground-observer is `queue: .main`, and
// every caller is a SwiftUI view). The annotation codifies that contract so
// Swift 6 strict concurrency doesn't regress us.
@MainActor
class RestTimer: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    @Published var isActive: Bool = false
    @Published var totalTime: TimeInterval = 0
    @Published var originalTotalTime: TimeInterval = 0
    @Published var adElapsedTime: TimeInterval = 0
    @Published var shouldAnimate: Bool = true
    
    private var displayLink: CADisplayLink?
    private var endDate: Date?
    private var foregroundObserver: NSObjectProtocol?
    
    var visualProgress: CGFloat {
        guard originalTotalTime > 0 else { return 0 }
        return CGFloat((originalTotalTime - timeRemaining) / originalTotalTime)
    }
    
    var visualRemainingProgress: CGFloat {
        1.0 - visualProgress
    }
    
    init() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncToWallClock()
        }
    }
    
    deinit {
        displayLink?.invalidate()
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// ⚡️ PERF (2026-07-31 finding H): every ExerciseCard observing this
    /// timer used to re-evaluate its body at display refresh rate (60–120 Hz)
    /// for the whole rest period, because the CADisplayLink published
    /// `timeRemaining` on every frame. The link is now capped at 1–4 fps
    /// AND `tick` only publishes when the whole second flips.
    private func makeDisplayLink() -> CADisplayLink {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 4, preferred: 2)
        return link
    }
    
    func syncToWallClock() {
        guard let endDate = endDate else { return }
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = 0
            stop()
        } else {
            timeRemaining = remaining
            if !isActive { isActive = true }
            if displayLink == nil {
                displayLink = makeDisplayLink()
                displayLink?.add(to: .main, forMode: .common)
            }
        }
    }
    
    func start(duration: TimeInterval) {
        startWithAdOffset(duration: duration, originalTotal: duration, adTime: 0)
    }
    
    func startWithAdOffset(duration: TimeInterval, originalTotal: TimeInterval, adTime: TimeInterval) {
        stop()
        
        totalTime = duration
        timeRemaining = duration
        originalTotalTime = originalTotal
        adElapsedTime = adTime
        isActive = true
        shouldAnimate = true
        let endsAt = Date().addingTimeInterval(duration)
        endDate = endsAt

        displayLink = makeDisplayLink()
        displayLink?.add(to: .main, forMode: .common)

        // Mirror the rest-end timestamp to the watch so it can fire
        // a wrist-tap haptic the moment the timer expires. No-op
        // when no watch is paired/installed (PE invariant 33).
        Task { @MainActor in
            PhoneToWatchLiveWorkoutBridge.shared.pushRestEndsAt(endsAt)
        }
    }
    
    func enableAnimation() {
        shouldAnimate = true
    }
    
    @objc private func tick(_ link: CADisplayLink) {
        guard let endDate = endDate else { return }
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = 0
            stop()
        } else if Int(remaining) != Int(timeRemaining) {
            // Publish only when the whole second changes — observers render
            // seconds, so intra-second publishes were pure invalidation churn.
            timeRemaining = remaining
        }
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        endDate = nil
        isActive = false
        timeRemaining = 0
        adElapsedTime = 0
        originalTotalTime = 0

        // Clear the watch's rest-timer slot so a previously-scheduled
        // wrist tap doesn't fire after the user manually stops/skips.
        Task { @MainActor in
            PhoneToWatchLiveWorkoutBridge.shared.pushRestEndsAt(nil)
        }
    }
    
    func pause() {
        displayLink?.invalidate()
        displayLink = nil
        endDate = nil
        isActive = false
    }
    
    func resume() {
        guard timeRemaining > 0 else { return }
        isActive = true
        endDate = Date().addingTimeInterval(timeRemaining)
        displayLink = makeDisplayLink()
        displayLink?.add(to: .main, forMode: .common)
    }
}

struct RestTimerView: View {
    @Binding var restTimer: RestTimer
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                
                // Timer display
                Text(formatTime(restTimer.timeRemaining))
                    .font(.system(size: 60, weight: .light, design: .monospaced))
                    .foregroundColor(.blue)
                
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(1 - (restTimer.timeRemaining / restTimer.totalTime)))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                }
                
                // Control buttons
                HStack(spacing: 30) {
                    Button(action: {
                        if restTimer.isActive {
                            restTimer.pause()
                        } else {
                            restTimer.resume()
                        }
                    }) {
                        Image(systemName: restTimer.isActive ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        restTimer.stop()
                        isPresented = false
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
            }
                .navigationTitle("Rest Timer")
                .navigationBarTitleDisplayMode(.inline)
                .adaptiveToolbarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Rest Timer Setup View
struct RestTimerSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let onSetTimer: (TimeInterval) -> Void

    @State private var selectedMinutes: Int = 2
    @State private var selectedSeconds: Int = 0

    private let minuteOptions = Array(0...10)
    private let secondOptions = Array(stride(from: 0, to: 60, by: 15))

    // Sprint 5 F-6: Canonical rest-time presets.
    // Chosen from common training protocols:
    //   - 30s/45s: conditioning/superset
    //   - 60s/90s: hypertrophy
    //   - 2m/3m: strength/compound
    //   - 5m: max-effort / heavy singles
    private static let presetDurations: [TimeInterval] = [30, 45, 60, 90, 120, 180, 300]

    private var totalSeconds: TimeInterval {
        TimeInterval(selectedMinutes * 60 + selectedSeconds)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Static orb background — matches the active workout / rename
                // sheet for visual consistency. Static (no animation loop) so
                // the runloop stays free for the rest timer + audio playback
                // running in the parent active workout.
                AnimatedOrbBackground.workoutStatic(colorScheme: colorScheme)
                
                VStack(spacing: 24) {
                    Text("Set Rest Timer")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Choose how long to rest between sets for this exercise")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Sprint 5 F-6: quick preset chips so users can one-tap a
                    // standard rest interval without scrolling two pickers.
                    presetChips

                    // Time picker
                    HStack(spacing: 20) {
                        VStack {
                            Text("Minutes")
                                .font(.headline)
                            Picker("Minutes", selection: $selectedMinutes) {
                                ForEach(minuteOptions, id: \.self) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 100, height: 150)
                        }

                        VStack {
                            Text("Seconds")
                                .font(.headline)
                            Picker("Seconds", selection: $selectedSeconds) {
                                ForEach(secondOptions, id: \.self) { second in
                                    Text("\(second)").tag(second)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 100, height: 150)
                        }
                    }

                    // Preview
                    Text("Rest Time: \(selectedMinutes):\(String(format: "%02d", selectedSeconds))")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)

                    Spacer()
                }
                .padding()
            }
                .navigationTitle("Rest Timer")
                .navigationBarTitleDisplayMode(.inline)
                .adaptiveToolbarBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Set") {
                        let totalSeconds = TimeInterval(selectedMinutes * 60 + selectedSeconds)
                        onSetTimer(totalSeconds)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sprint 5 F-6: Preset Chips

    @ViewBuilder
    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.presetDurations, id: \.self) { preset in
                    presetChip(for: preset)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    @ViewBuilder
    private func presetChip(for seconds: TimeInterval) -> some View {
        let isSelected = Int(totalSeconds) == Int(seconds)
        Button(action: { applyPreset(seconds) }) {
            Text(Self.formatPreset(seconds))
                .font(.ds_labelMedium)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : .blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color.blue.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.blue.opacity(isSelected ? 0.0 : 0.25), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Rest \(Self.formatPreset(seconds))")
        .accessibilityHint("Sets rest timer to \(Self.formatPreset(seconds))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func applyPreset(_ seconds: TimeInterval) {
        HapticManager.impact(.light)
        let total = Int(seconds)
        selectedMinutes = total / 60
        // Snap to nearest 15s bucket matching secondOptions.
        let remainder = total % 60
        let snapped = secondOptions.min(by: {
            abs($0 - remainder) < abs($1 - remainder)
        }) ?? 0
        selectedSeconds = snapped
    }

    private static func formatPreset(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        let m = total / 60
        let s = total % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}
