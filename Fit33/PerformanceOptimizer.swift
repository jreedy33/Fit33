import SwiftUI
import UIKit
import CoreData

// MARK: - Performance Optimizer (Apple PRE Senior Engineer Approach)
/// Centralized performance optimizations for buttery-smooth 60fps experience
/// Key principles: Immediate feedback, minimal main thread work, efficient view updates
/// Note: HapticManager is defined in SharedUtilities.swift

// MARK: - Fast Animations (60fps Optimized)
/// Animation presets optimized for perceived speed
struct FastAnimations {
    // MARK: - Instant (No animation)
    static let none: Animation? = nil
    
    // MARK: - Ultra-fast (for tap feedback)
    static let instant = Animation.linear(duration: 0.08)
    
    // MARK: - Fast (for UI state changes)
    static let fast = Animation.easeOut(duration: 0.15)
    
    // MARK: - Standard (for screen transitions)
    static let standard = Animation.easeInOut(duration: 0.2)
    
    // MARK: - Spring (for bouncy interactions)
    static let spring = Animation.spring(response: 0.25, dampingFraction: 0.75)
    static let snappy = Animation.spring(response: 0.2, dampingFraction: 0.8)
    static let bouncy = Animation.spring(response: 0.3, dampingFraction: 0.6)
    
    // MARK: - Sheet presentations
    static let sheet = Animation.spring(response: 0.28, dampingFraction: 0.82)
}

// MARK: - View Modifiers for Performance

/// Immediate tap feedback modifier
struct ImmediateTapModifier: ViewModifier {
    let action: () -> Void
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
            .animation(FastAnimations.instant, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            HapticManager.lightTap()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        action()
                    }
            )
    }
}

/// Button with immediate haptic feedback
struct FastButtonStyle: ButtonStyle {
    let feedbackStyle: FeedbackStyle
    
    enum FeedbackStyle {
        case light, medium, heavy, selection
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(FastAnimations.instant, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    switch feedbackStyle {
                    case .light: HapticManager.lightTap()
                    case .medium: HapticManager.tap()
                    case .heavy: HapticManager.heavyTap()
                    case .selection: HapticManager.selectionChanged()
                    }
                }
            }
    }
}

/// High-performance row for lists (minimal view hierarchy)
struct FastListRow<Content: View>: View {
    let content: () -> Content
    var onTap: (() -> Void)? = nil
    
    @State private var isPressed = false
    
    var body: some View {
        content()
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(FastAnimations.instant, value: isPressed)
            .onTapGesture {
                HapticManager.tap()
                onTap?()
            }
            .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
    }
}

// MARK: - Extensions

extension View {
    /// Add immediate tap feedback to any view
    func immediateTap(action: @escaping () -> Void) -> some View {
        modifier(ImmediateTapModifier(action: action))
    }
    
    /// Optimized for scroll performance - reduces view complexity during scroll
    func scrollOptimized() -> some View {
        self
            .drawingGroup() // Flattens view hierarchy for faster rendering
    }
    
    /// Fast fade-in for appearing content
    func fastFadeIn() -> some View {
        self
            .transition(.opacity.animation(FastAnimations.fast))
    }
    
    /// Ultra-fast scale animation for tap feedback
    @ViewBuilder
    func tapScale(isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(FastAnimations.instant, value: isPressed)
    }
}

extension Button {
    /// Apply fast button style with haptic feedback
    func fastStyle(_ style: FastButtonStyle.FeedbackStyle = .medium) -> some View {
        self.buttonStyle(FastButtonStyle(feedbackStyle: style))
    }
}

// MARK: - Optimized List Components

/// High-performance exercise row with minimal view complexity
struct OptimizedExerciseRow: View {
    let name: String
    let category: String?
    let equipment: String?
    let categoryColor: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Simple icon circle (no gradients for scroll perf)
            Circle()
                .fill(categoryColor)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.ds_labelLarge)
                        .foregroundColor(.white)
                )
            
            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let category = category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(categoryColor)
                    }
                    
                    if let equipment = equipment {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(equipment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Spacing.sm)
        .background(Color(.systemBackground).opacity(0.8))
        .cornerRadius(CornerRadius.md)
    }
}

// MARK: - Performance Monitoring (Debug Only)

#if DEBUG
final class DebugPerformanceMonitor {
    static let shared = DebugPerformanceMonitor()
    
    private var frameDrops = 0
    private var lastFrameTime: CFTimeInterval = 0
    
    func trackFrame() {
        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            let frameDuration = currentTime - lastFrameTime
            // Frame should be ~16.67ms for 60fps
            if frameDuration > 0.02 { // More than 20ms = dropped frame
                frameDrops += 1
                print("⚠️ [PERF] Frame drop detected: \(String(format: "%.1f", frameDuration * 1000))ms")
            }
        }
        lastFrameTime = currentTime
    }
    
    func logMetric(_ name: String, value: Double, unit: String = "ms") {
        print("📊 [PERF] \(name): \(String(format: "%.2f", value))\(unit)")
    }
    
    func measureBlock(_ name: String, block: () -> Void) {
        let start = CACurrentMediaTime()
        block()
        let elapsed = (CACurrentMediaTime() - start) * 1000
        logMetric(name, value: elapsed)
    }
    
    func measureBlockAsync(_ name: String, block: () async -> Void) async {
        let start = CACurrentMediaTime()
        await block()
        let elapsed = (CACurrentMediaTime() - start) * 1000
        logMetric(name, value: elapsed)
    }
}
#endif

// MARK: - Scroll Performance Optimizer

/// Tracks scroll velocity to reduce work during fast scrolling
final class ScrollPerformanceTracker: ObservableObject {
    static let shared = ScrollPerformanceTracker()
    
    @Published private(set) var isScrollingFast = false
    
    private var lastOffset: CGFloat = 0
    private var lastTime: CFTimeInterval = 0
    private var velocity: CGFloat = 0
    
    private let fastScrollThreshold: CGFloat = 500 // points per second
    
    func updateScroll(offset: CGFloat) {
        let currentTime = CACurrentMediaTime()
        if lastTime > 0 {
            let timeDelta = currentTime - lastTime
            let offsetDelta = abs(offset - lastOffset)
            velocity = offsetDelta / CGFloat(timeDelta)
            
            let wasFast = isScrollingFast
            isScrollingFast = velocity > fastScrollThreshold
            
            // Only publish if changed to avoid unnecessary view updates
            if wasFast != isScrollingFast {
                objectWillChange.send()
            }
        }
        lastOffset = offset
        lastTime = currentTime
    }
    
    func resetScroll() {
        isScrollingFast = false
        velocity = 0
    }
}

// MARK: - Image Loading Optimizer

/// Async image loading with memory caching
actor ImageCache {
    static let shared = ImageCache()
    
    private var cache = NSCache<NSString, UIImage>()
    
    init() {
        cache.countLimit = 100 // Max 100 images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}

// MARK: - Debouncer for Search/Filter

final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue
    private let delay: TimeInterval
    
    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }
    
    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
    
    func cancel() {
        workItem?.cancel()
    }
}

// MARK: - Exercise Filter Cache (High-Performance)
/// Caches filtered exercise results to avoid recomputation on every render
/// Key insight: Filter changes are infrequent, but renders are constant

final class ExerciseFilterCache: ObservableObject {
    static let shared = ExerciseFilterCache()
    
    // Cache keyed by filter combination hash
    private var cache: [String: [NSManagedObjectID]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.fit33.filterCache", qos: .userInteractive)
    
    // Debouncer for filter updates
    private let filterDebouncer = Debouncer(delay: 0.05) // 50ms debounce
    
    private init() {}
    
    /// Generate cache key from filter parameters
    func cacheKey(
        category: String,
        equipment: String,
        muscleGroup: String,
        searchText: String,
        filterType: String,
        exerciseTypes: Set<String>
    ) -> String {
        let typesKey = exerciseTypes.sorted().joined(separator: ",")
        return "\(category)|\(equipment)|\(muscleGroup)|\(searchText.lowercased())|\(filterType)|\(typesKey)"
    }
    
    /// Get cached results if available
    func getCachedResults(for key: String) -> [NSManagedObjectID]? {
        cacheQueue.sync {
            cache[key]
        }
    }
    
    /// Store filtered results
    func cacheResults(_ results: [NSManagedObjectID], for key: String) {
        cacheQueue.async { [weak self] in
            self?.cache[key] = results
            
            // Limit cache size to 20 entries
            if let count = self?.cache.count, count > 20 {
                // Remove oldest entries (simple FIFO for now)
                let keysToRemove = self?.cache.keys.prefix(count - 15)
                keysToRemove?.forEach { self?.cache.removeValue(forKey: $0) }
            }
        }
    }
    
    /// Invalidate all cache (call when exercise list changes)
    func invalidateAll() {
        cacheQueue.async { [weak self] in
            self?.cache.removeAll()
        }
    }
    
    /// Invalidate cache entries containing search text
    func invalidateSearchCache() {
        cacheQueue.async { [weak self] in
            self?.cache = self?.cache.filter { key, _ in
                // Keep entries without search text
                let parts = key.split(separator: "|")
                return parts.count >= 4 && parts[3].isEmpty
            } ?? [:]
        }
    }
}

// MARK: - Async Filter Task Manager
/// Manages background filtering to keep UI responsive

actor AsyncFilterManager {
    static let shared = AsyncFilterManager()
    
    private var currentTask: Task<Void, Never>?
    
    func scheduleFilter(
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async -> Void
    ) {
        // Cancel previous filter task
        currentTask?.cancel()
        
        // Start new filter task
        currentTask = Task(priority: priority) {
            await operation()
        }
    }
    
    func cancelCurrentFilter() {
        currentTask?.cancel()
    }
}

// MARK: - Navigation Preloader
/// Preloads next likely screens for instant transitions

final class NavigationPreloader {
    static let shared = NavigationPreloader()
    
    private var preloadedViews: [String: AnyView] = [:]
    private var lastPreloadTime: [String: Date] = [:]
    private let preloadQueue = DispatchQueue(label: "com.fit33.preload", qos: .background)
    
    private init() {}
    
    /// Hint that user might navigate to a destination
    func hint(destination: String) {
        // Only preload if not recently preloaded
        let now = Date()
        if let lastTime = lastPreloadTime[destination],
           now.timeIntervalSince(lastTime) < 30 {
            return
        }
        
        lastPreloadTime[destination] = now
        
        preloadQueue.async {
            // Preload video assets for likely destinations
            if destination.contains("Exercise") {
                VideoPlaybackEngine.shared.preWarmRecentExercises()
            }
        }
    }
    
    /// Clear preloaded content
    func clearPreloads() {
        preloadedViews.removeAll()
    }
}

// MARK: - Main Thread Guard
/// Ensures heavy work stays off main thread

enum MainThreadGuard {
    /// Check if on main thread in debug builds
    @inline(__always)
    static func ensureMainThread(file: String = #file, line: Int = #line) {
        #if DEBUG
        assert(Thread.isMainThread, "Expected main thread at \(file):\(line)")
        #endif
    }
    
    /// Check if off main thread in debug builds
    @inline(__always)
    static func ensureBackgroundThread(file: String = #file, line: Int = #line) {
        #if DEBUG
        assert(!Thread.isMainThread, "Expected background thread at \(file):\(line)")
        #endif
    }
    
    /// Run on main thread (sync if already there, async otherwise)
    static func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

// MARK: - View Performance Extensions

extension View {
    /// Optimizes view for scroll lists - reduces complexity during fast scroll
    @ViewBuilder
    func optimizedForScroll(_ isScrollingFast: Bool) -> some View {
        if isScrollingFast {
            // Simplified view during fast scroll
            self
                .drawingGroup() // Flatten view hierarchy
        } else {
            self
        }
    }
    
    /// Add immediate tap response with haptic
    func fastTap(action: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    HapticManager.tap()
                    action()
                }
        )
    }
    
    /// Preload destination when view appears
    func preloadDestination(_ destination: String) -> some View {
        self.onAppear {
            NavigationPreloader.shared.hint(destination: destination)
        }
    }
}
