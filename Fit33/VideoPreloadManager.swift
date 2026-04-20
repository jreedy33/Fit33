import Foundation
import AVKit
import Combine

// MARK: - Advanced Video Preload Manager
/// Intelligent video prefetching for 7000+ exercise library
/// Features:
/// - Viewport-aware prefetching (only load visible + nearby)
/// - Scroll direction prediction
/// - Priority queue with cancellation
/// - Memory-efficient LRU cache
/// - Bandwidth throttling
/// - Background processing

// 🔍 ADVANCED LOGGING
private func prefetchLog(_ message: String, level: String = "INFO") {
    #if DEBUG
    let timestamp = ISO8601DateFormatter().string(from: Date())
    AppLogger.debug("[\(timestamp)] 🎬 PREFETCH [\(level)]: \(message)", category: .general)
    #endif
}

final class VideoPreloadManager: ObservableObject {
    static let shared = VideoPreloadManager()
    
    // MARK: - Configuration
    // ⚡️ MEMORY FIX: Aggressively reduced to prevent 600MB+ footprint.
    // Each AVPlayer with buffered video = 20-50MB. We had 3 caching systems competing.
    private struct Config {
        static let maxCachedPlayers = 3           // Was 10 — only cache what's visible
        static let prefetchAhead = 2              // Was 5
        static let prefetchBehind = 0             // Was 2 — don't cache what user already scrolled past
        static let maxConcurrentDownloads = 1     // Was 2 — one at a time to avoid memory spikes
        static let bufferDuration: TimeInterval = 1.5  // Was 2.0 — less buffer = less RAM
        static let lowMemoryThreshold = 1         // Was 8 — on low memory, keep only 1
        static let scrollVelocityThreshold: CGFloat = 50
        static let debounceInterval: TimeInterval = 0.3
    }
    
    // MARK: - State
    @Published private(set) var isPreloading = false
    @Published private(set) var cachedCount = 0
    
    // LRU Cache for preloaded players
    private var playerCache: [String: CachedPlayer] = [:]
    private var cacheOrder: [String] = [] // Most recent at end
    
    // Prefetch queue
    private var prefetchQueue: [PrefetchRequest] = []
    private var activeFetches: Set<String> = []
    private let fetchLock = NSLock()
    
    // Scroll tracking
    private var lastVisibleIndices: [Int] = []
    private var scrollDirection: ScrollDirection = .none
    private var scrollVelocity: CGFloat = 0
    private var lastScrollTime: Date = Date()
    
    // Cloudflare R2 base URL
    private let baseURL = "https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev"
    
    // Video filename cache (from database)
    private var videoFilenameCache: [String: String] = [:]
    private var videoCodeCache: [String: String] = [:]
    
    // Queues
    private let prefetchQueue_serial = DispatchQueue(label: "video.prefetch", qos: .utility)
    private let cacheQueue = DispatchQueue(label: "video.cache", qos: .userInitiated)
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Types
    
    private struct CachedPlayer {
        let player: AVPlayer
        let exerciseName: String
        let createdAt: Date
        var lastAccessed: Date
        var isBuffered: Bool
    }
    
    private struct PrefetchRequest: Equatable {
        let exerciseName: String
        let videoFilename: String
        let priority: Priority
        let requestTime: Date
        
        enum Priority: Int, Comparable {
            case immediate = 0   // User tapped
            case visible = 1     // Currently on screen
            case upcoming = 2    // About to scroll into view
            case background = 3  // Pre-warm cache
            
            static func < (lhs: Priority, rhs: Priority) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
        
        static func == (lhs: PrefetchRequest, rhs: PrefetchRequest) -> Bool {
            lhs.exerciseName == rhs.exerciseName
        }
    }
    
    enum ScrollDirection {
        case up, down, none
    }
    
    // Debounce timer
    private var debounceWorkItem: DispatchWorkItem?
    private var isProcessing = false
    
    // MARK: - Initialization
    
    private init() {
        prefetchLog("VideoPreloadManager initializing...", level: "INIT")
        setupMemoryWarningObserver()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            self?.loadVideoMappingsFromDatabase()
        }
        prefetchLog("VideoPreloadManager initialized", level: "INIT")
    }
    
    // MARK: - Public API
    
    /// Call this when visible exercises change (from LazyVStack/ScrollView)
    /// SAFE: Debounced and defensive to prevent crashes
    func updateVisibleExercises(_ exerciseNames: [String], at indices: [Int]) {
        // SAFETY: Validate inputs
        guard !exerciseNames.isEmpty else {
            prefetchLog("updateVisibleExercises called with empty names - skipping", level: "WARN")
            return
        }
        
        guard !indices.isEmpty else {
            prefetchLog("updateVisibleExercises called with empty indices - skipping", level: "WARN")
            return
        }
        
        // DEBOUNCE: Cancel previous work and schedule new
        debounceWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.performVisibleExercisesUpdate(exerciseNames, at: indices)
        }
        debounceWorkItem = workItem
        
        // Execute after debounce interval
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Config.debounceInterval))
            workItem.perform()
        }
    }
    
    private func performVisibleExercisesUpdate(_ exerciseNames: [String], at indices: [Int]) {
        // Prevent re-entrant calls
        guard !isProcessing else {
            prefetchLog("Already processing - skipping update", level: "SKIP")
            return
        }

        // Sprint 3 (Q2-30): respect cellular / Low Data Mode. Users on expensive
        // or constrained connections still get on-demand playback (handled in
        // RemoteVideoPlayerView). Only the speculative prefetcher is gated here.
        if NetworkMonitor.shared.shouldAvoidBackgroundTraffic {
            prefetchLog("Prefetch skipped — expensive/constrained network (Low Data Mode or cellular)", level: "SKIP")
            return
        }

        isProcessing = true
        defer { isProcessing = false }
        
        prefetchLog("Processing \(exerciseNames.count) visible exercises at indices \(indices.first ?? -1)...\(indices.last ?? -1)", level: "UPDATE")
        
        // Safely calculate scroll direction
        let currentFirst = indices.first ?? 0
        let lastFirst = lastVisibleIndices.first ?? currentFirst
        
        if currentFirst > lastFirst {
            scrollDirection = .down
        } else if currentFirst < lastFirst {
            scrollDirection = .up
        }
        
        // Calculate scroll velocity safely
        let now = Date()
        let timeDelta = max(0.001, now.timeIntervalSince(lastScrollTime)) // Prevent division by zero
        let indexDelta = abs(currentFirst - lastFirst)
        
        // Smooth velocity calculation
        let newVelocity = min(1000, CGFloat(indexDelta) / CGFloat(timeDelta))
        scrollVelocity = scrollVelocity * 0.7 + newVelocity * 0.3 // Smoothing
        
        lastScrollTime = now
        lastVisibleIndices = indices
        
        prefetchLog("Scroll direction: \(scrollDirection), velocity: \(Int(scrollVelocity))", level: "SCROLL")
        
        // Don't prefetch during fast scrolling
        guard scrollVelocity < Config.scrollVelocityThreshold else {
            prefetchLog("Prefetch paused - fast scrolling (velocity: \(Int(scrollVelocity)))", level: "PAUSE")
            return
        }
        
        // Queue prefetch for visible items only (limit to prevent overload)
        let namesToPrefetch = Array(exerciseNames.prefix(Config.prefetchAhead))
        prefetchLog("Queueing \(namesToPrefetch.count) exercises for prefetch", level: "QUEUE")
        
        for name in namesToPrefetch {
            queuePrefetch(for: name, priority: .visible)
        }
        
        // Process queue in background
        prefetchQueue_serial.async { [weak self] in
            self?.processPrefetchQueue()
        }
    }
    
    // Track what we've already queued to prevent spam
    private var recentlyQueued: Set<String> = []
    private var lastQueueCleanup = Date()
    
    /// Call when user is about to tap on an exercise
    /// DISABLED FOR NOW - prefetching causes performance issues with large libraries
    func prioritizePrefetch(for exerciseName: String) {
        // 🚫 DISABLED: Prefetching is causing major lag with 7000+ exercises
        // Videos will load on-demand when user taps an exercise
        // This provides a better UX than trying to prefetch everything
        return
        
        // --- Original code below (disabled) ---
        /*
        guard !exerciseName.isEmpty else { return }
        
        let normalized = exerciseName.lowercased()
        
        // Prevent spam - don't re-queue recently queued items
        if recentlyQueued.contains(normalized) { return }
        
        // Cleanup old entries every 30 seconds
        if Date().timeIntervalSince(lastQueueCleanup) > 30 {
            recentlyQueued.removeAll()
            lastQueueCleanup = Date()
        }
        
        recentlyQueued.insert(normalized)
        
        prefetchQueue_serial.async { [weak self] in
            self?.queuePrefetch(for: exerciseName, priority: .immediate)
            self?.processPrefetchQueue()
        }
        */
    }
    
    /// Get a preloaded player instantly, or nil if not cached
    func getPreloadedPlayer(for exerciseName: String) -> AVPlayer? {
        cacheQueue.sync {
            if var cached = playerCache[exerciseName.lowercased()] {
                cached.lastAccessed = Date()
                playerCache[exerciseName.lowercased()] = cached
                
                // Move to end of LRU
                if let idx = cacheOrder.firstIndex(of: exerciseName.lowercased()) {
                    cacheOrder.remove(at: idx)
                    cacheOrder.append(exerciseName.lowercased())
                }
                
                #if DEBUG
                AppLogger.debug("⚡ Instant playback: \(exerciseName)", category: .general)
                #endif
                return cached.player
            }
            return nil
        }
    }
    
    /// Get or create player (with immediate loading if not cached)
    func getPlayer(for exerciseName: String, videoFilename: String? = nil) -> AVPlayer? {
        // Check cache first
        if let cached = getPreloadedPlayer(for: exerciseName) {
            return cached
        }
        
        // Not cached - load immediately
        guard let url = getVideoURL(for: exerciseName, videoFilename: videoFilename) else {
            return nil
        }
        
        let player = createOptimizedPlayer(url: url)
        addToCache(exerciseName: exerciseName, player: player)
        
        return player
    }
    
    /// Clear cache (call on memory warning)
    func clearCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            for cached in self.playerCache.values {
                cached.player.pause()
                cached.player.replaceCurrentItem(with: nil)
            }
            self.playerCache.removeAll()
            self.cacheOrder.removeAll()
            
            DispatchQueue.main.async {
                self.cachedCount = 0
            }
            
            #if DEBUG
            AppLogger.debug("🧹 Video cache cleared", category: .general)
            #endif
        }
    }
    
    /// Reduce cache to minimum (for low memory situations)
    func reduceCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Keep only most recent items
            while self.playerCache.count > Config.lowMemoryThreshold {
                if let oldest = self.cacheOrder.first {
                    self.evictFromCache(oldest)
                }
            }
            
            #if DEBUG
            AppLogger.debug("📉 Cache reduced to \(self.playerCache.count) items", category: .general)
            #endif
        }
    }
    
    // MARK: - Private Methods
    
    private func queuePrefetch(for exerciseName: String, priority: PrefetchRequest.Priority) {
        fetchLock.lock()
        defer { fetchLock.unlock() }
        
        let normalizedName = exerciseName.lowercased()
        
        // Skip if already cached or fetching
        if playerCache[normalizedName] != nil || activeFetches.contains(normalizedName) {
            return
        }
        
        // Get video filename
        guard let filename = getVideoFilename(for: exerciseName) else {
            return
        }
        
        // Remove existing request for this exercise (if lower priority)
        prefetchQueue.removeAll { $0.exerciseName.lowercased() == normalizedName }
        
        let request = PrefetchRequest(
            exerciseName: exerciseName,
            videoFilename: filename,
            priority: priority,
            requestTime: Date()
        )
        
        prefetchQueue.append(request)
        prefetchQueue.sort { $0.priority < $1.priority }
    }
    
    private func processPrefetchQueue() {
        prefetchQueue_serial.async { [weak self] in
            guard let self = self else { return }
            
            self.fetchLock.lock()
            
            // Don't exceed concurrent download limit
            guard self.activeFetches.count < Config.maxConcurrentDownloads else {
                self.fetchLock.unlock()
                return
            }
            
            // Get next request
            guard let request = self.prefetchQueue.first else {
                self.fetchLock.unlock()
                return
            }
            
            self.prefetchQueue.removeFirst()
            let normalizedName = request.exerciseName.lowercased()
            self.activeFetches.insert(normalizedName)
            self.fetchLock.unlock()
            
            // Create and buffer player
            let urlString = "\(self.baseURL)/\(request.videoFilename)"
            guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else {
                self.fetchLock.lock()
                self.activeFetches.remove(normalizedName)
                self.fetchLock.unlock()
                return
            }
            
            DispatchQueue.main.async {
                let player = self.createOptimizedPlayer(url: url)
                
                // Start buffering
                player.currentItem?.preferredForwardBufferDuration = Config.bufferDuration
                
                self.addToCache(exerciseName: request.exerciseName, player: player)
                
                self.fetchLock.lock()
                self.activeFetches.remove(normalizedName)
                self.fetchLock.unlock()
                
                // Process next in queue
                self.processPrefetchQueue()
                
                #if DEBUG
                if request.priority == .visible {
                    AppLogger.debug("📥 Prefetched (visible): \(request.exerciseName)", category: .general)
                }
                #endif
            }
        }
    }
    
    private func addToCache(exerciseName: String, player: AVPlayer) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let normalizedName = exerciseName.lowercased()
            
            // Evict if at capacity
            while self.playerCache.count >= Config.maxCachedPlayers {
                if let oldest = self.cacheOrder.first {
                    self.evictFromCache(oldest)
                }
            }
            
            let cached = CachedPlayer(
                player: player,
                exerciseName: exerciseName,
                createdAt: Date(),
                lastAccessed: Date(),
                isBuffered: false
            )
            
            self.playerCache[normalizedName] = cached
            self.cacheOrder.append(normalizedName)
            
            DispatchQueue.main.async {
                self.cachedCount = self.playerCache.count
            }
        }
    }
    
    private func evictFromCache(_ name: String) {
        if let cached = playerCache[name] {
            cached.player.pause()
            cached.player.replaceCurrentItem(with: nil)
        }
        playerCache.removeValue(forKey: name)
        cacheOrder.removeAll { $0 == name }
        
        #if DEBUG
        AppLogger.debug("🗑️ Evicted: \(name)", category: .general)
        #endif
    }
    
    private func createOptimizedPlayer(url: URL) -> AVPlayer {
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetPreferPreciseDurationAndTimingKey": false,
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4"
        ])
        
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        playerItem.preferredForwardBufferDuration = Config.bufferDuration
        
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        
        return player
    }
    
    private func getVideoURL(for exerciseName: String, videoFilename: String? = nil) -> URL? {
        let filename: String
        
        if let provided = videoFilename, !provided.isEmpty {
            filename = provided
        } else if let cached = getVideoFilename(for: exerciseName) {
            filename = cached
        } else {
            return nil
        }
        
        let urlString = "\(baseURL)/\(filename)"
        return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
    }
    
    private func getVideoFilename(for exerciseName: String) -> String? {
        let normalized = exerciseName.lowercased()
        
        // Check filename cache
        if let filename = videoFilenameCache[normalized] {
            return filename
        }
        
        // Check code cache
        if let filename = videoCodeCache[normalized] {
            return filename
        }
        
        // Fall back to VideoStreamingService
        return VideoStreamingService.shared.videoFilenameCache[normalized]
    }
    
    // MARK: - Database Loading
    
    // ⚡️ MEMORY FIX: Removed duplicate Supabase fetch. VideoPreloadManager was fetching
    // 2000+ exercise→video mappings into its own dictionaries, duplicating what
    // VideoStreamingService already fetches and caches. Now we just rely on
    // VideoStreamingService.shared.videoFilenameCache via getVideoFilename() fallback.
    private func loadVideoMappingsFromDatabase() {
        prefetchLog("Skipping duplicate mapping fetch — using VideoStreamingService cache", level: "DB")
        // No-op: videoFilenameCache and videoCodeCache are no longer populated here.
        // getVideoFilename() already falls back to VideoStreamingService.shared.videoFilenameCache.
    }
    
    // MARK: - Memory Management
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.reduceCache()
            }
            .store(in: &cancellables)
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// Modifier to track visible exercises in a ScrollView/LazyVStack
struct VisibilityTracker: ViewModifier {
    let exerciseName: String
    let index: Int
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                // Notify preload manager
                VideoPreloadManager.shared.prioritizePrefetch(for: exerciseName)
            }
            .onDisappear {
                isVisible = false
            }
    }
}

extension View {
    /// Track visibility for video prefetching
    func trackVisibility(exerciseName: String, index: Int) -> some View {
        modifier(VisibilityTracker(exerciseName: exerciseName, index: index))
    }
}

// MARK: - Scroll Position Tracker

/// Preference key to track scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// View that reports visible items in a LazyVStack
struct VisibleItemsTracker<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let itemHeight: CGFloat
    let content: (Item, Int) -> Content
    let onVisibleItemsChanged: ([Int]) -> Void
    
    @State private var visibleRange: Range<Int> = 0..<0
    
    var body: some View {
        GeometryReader { outerGeometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        content(item, index)
                            .frame(height: itemHeight)
                            .background(
                                GeometryReader { itemGeometry in
                                    Color.clear
                                        .preference(
                                            key: ScrollOffsetPreferenceKey.self,
                                            value: itemGeometry.frame(in: .named("scroll")).minY
                                        )
                                }
                            )
                    }
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                let viewportHeight = outerGeometry.size.height
                let firstVisible = max(0, Int(-offset / itemHeight))
                let lastVisible = min(items.count - 1, Int((-offset + viewportHeight) / itemHeight))
                
                let newRange = firstVisible..<(lastVisible + 1)
                if newRange != visibleRange {
                    visibleRange = newRange
                    onVisibleItemsChanged(Array(newRange))
                }
            }
        }
    }
}

