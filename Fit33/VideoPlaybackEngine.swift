import Foundation
import AVKit
import Combine
import SwiftUI

// MARK: - YouTube-Style Video Playback Engine
/// High-performance video system designed for instant playback
/// Key features:
/// - Zero-delay playback (starts playing immediately, buffers in background)
/// - Smart priority caching (favorites/recent in hot cache)
/// - Predictive prefetching based on user navigation
/// - First-frame extraction for instant visual feedback
/// - Memory-efficient with aggressive LRU eviction

final class VideoPlaybackEngine: ObservableObject {
    static let shared = VideoPlaybackEngine()
    
    // MARK: - Configuration (YouTube-style)
    // ⚡️ MEMORY FIX: Drastically reduced cache sizes to prevent 600MB+ memory usage
    // Each AVPlayer + buffered video = 20-50MB. Old limits allowed 40+ players across 3 systems.
    private struct Config {
        // Cache tiers — REDUCED to prevent memory pressure killing network
        static let hotCacheSize = 2          // Only current + 1 favorite (was 5)
        static let warmCacheSize = 3         // Only most recent (was 15)
        static let maxTotalPlayers = 5       // Hard cap (was 20)
        
        // Buffering — REDUCED to lower per-player memory footprint
        static let minBufferForPlay: TimeInterval = 0.3    // Start playing after 300ms buffer
        static let targetBuffer: TimeInterval = 2.0         // Reduced from 3s
        static let maxBuffer: TimeInterval = 4.0            // Reduced from 8s
        
        // Prefetch — REDUCED to avoid creating players we don't need
        static let prefetchRadius = 1        // Only prefetch adjacent (was 3)
        static let maxConcurrentPrefetch = 1 // One at a time (was 2)
        
        // Persistence
        static let favoritesKey = "videoEngine_favorites"
        static let recentKey = "videoEngine_recent"
        static let maxRecentCount = 20
    }
    
    // MARK: - Storage URLs
    private let r2BaseURL = "https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev"
    
    // MARK: - Cache Tiers
    /// Hot cache: Favorites and currently active (instant access)
    private var hotCache: [String: CachedVideo] = [:]
    
    /// Warm cache: Recently used with LRU eviction
    private var warmCache: [String: CachedVideo] = [:]
    private var warmCacheOrder: [String] = []  // LRU tracking
    
    /// Video filename mappings from database
    private var videoMappings: [String: String] = [:]  // exerciseName.lowercased() -> filename
    private var mappingsLoaded = false
    
    // MARK: - Favorites & Recent
    /// User's favorite exercises (hardcoded for instant load)
    @Published private(set) var favoriteExercises: Set<String> = []
    
    /// Recently viewed exercises (for warm cache priority)
    private var recentExercises: [String] = []
    
    // MARK: - Prefetch State
    private var prefetchQueue: [PrefetchJob] = []
    private var activePrefetches: Set<String> = []
    private let prefetchLock = NSLock()
    
    // ⚡️ PERFORMANCE: Prevent duplicate pre-warming
    private var isPreWarmingInProgress = false
    private var lastPreWarmTime: Date?
    private let preWarmCooldown: TimeInterval = 30 // Only pre-warm every 30 seconds max
    
    // MARK: - Queues
    private let cacheQueue = DispatchQueue(label: "video.cache", qos: .userInitiated)
    private let prefetchQueue_bg = DispatchQueue(label: "video.prefetch", qos: .utility)
    private let mappingQueue = DispatchQueue(label: "video.mapping", qos: .background)
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Types
    
    private struct CachedVideo {
        let player: AVQueuePlayer
        var looper: AVPlayerLooper  // Mutable so we can recreate if cancelled
        let exerciseName: String
        let filename: String
        var createdAt: Date
        var lastAccessed: Date
        var isBuffered: Bool
        var tier: CacheTier
        
        enum CacheTier {
            case hot    // Favorites, current
            case warm   // Recently used
        }
    }
    
    private struct PrefetchJob {
        let exerciseName: String
        let filename: String
        let priority: Priority
        
        enum Priority: Int, Comparable {
            case immediate = 0  // User just tapped
            case adjacent = 1   // Next/prev in list
            case favorite = 2   // User's favorites
            case recent = 3     // Recently viewed
            
            static func < (lhs: Priority, rhs: Priority) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        loadFavorites()
        loadRecentExercises()
        setupMemoryWarning()
        configureAudioSession()
        
        // Load video mappings from database (non-blocking)
        loadVideoMappingsAsync()
        
        // Sync with Core Data favorites and pre-warm cache
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            self?.syncWithCoreDataFavorites()
            self?.preWarmFavorites()
        }
        
        // Listen for favorite changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FavoriteExerciseChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncWithCoreDataFavorites()
        }
        
        AppLogger.debug("VideoPlaybackEngine initialized", category: .general)
    }
    
    // MARK: - 🚀 PUBLIC API: Get Instant Player
    
    /// Get a ready-to-play video player with its looper (YouTube-style instant start)
    /// Priority: Hot cache → Warm cache → Create new (with instant-start)
    /// Returns tuple of (player, looper) to ensure looper doesn't get deallocated
    func getPlayerWithLooper(for exerciseName: String, videoFilename: String? = nil) -> (player: AVQueuePlayer, looper: AVPlayerLooper)? {
        let key = exerciseName.lowercased()
        
        // Track as recent
        trackRecentExercise(key)
        
        // Get the correct gender-aware filename we SHOULD be playing
        let expectedFilename = GenderFilterService.shared.getVideoFilename(for: exerciseName, fallbackToOpposite: true)
        
        // 1. Check hot cache first (favorites, current)
        if let cached = hotCache[key] {
            // ✅ VALIDATE: Ensure cached video matches current gender preference
            if let expected = expectedFilename, !expected.isEmpty, cached.filename != expected {
                AppLogger.debug("HOT cache invalid (wrong gender): \(exerciseName), cached: \(cached.filename), expected: \(expected)", category: .general)
                // Remove invalid cache entry and create new player
                hotCache.removeValue(forKey: key)
                guard let url = getVideoURL(for: key, videoFilename: videoFilename) else { return nil }
                return createInstantStartPlayerWithLooper(url: url, exerciseName: key, filename: expected)
            }
            
            hotCache[key]?.lastAccessed = Date()
            
            // ⚡️ CRITICAL: Don't seek on looping players - it cancels the looper!
            // Just play if paused
            if cached.player.timeControlStatus != .playing {
                cached.player.play()
            }
            
            AppLogger.debug("HOT cache hit: \(exerciseName)", category: .general)
            return (cached.player, cached.looper)
        }
        
        // 2. Check warm cache
        if let cached = warmCache[key] {
            // ✅ VALIDATE: Ensure cached video matches current gender preference
            if let expected = expectedFilename, !expected.isEmpty, cached.filename != expected {
                AppLogger.debug("WARM cache invalid (wrong gender): \(exerciseName), cached: \(cached.filename), expected: \(expected)", category: .general)
                // Remove invalid cache entry asynchronously (thread-safe)
                cacheQueue.async(flags: .barrier) { [weak self] in
                    self?.warmCache.removeValue(forKey: key)
                    self?.warmCacheOrder.removeAll { $0 == key }
                }
                guard let url = getVideoURL(for: key, videoFilename: videoFilename) else { return nil }
                return createInstantStartPlayerWithLooper(url: url, exerciseName: key, filename: expected)
            }
            
            promoteToHotIfFavorite(key)
            updateWarmCacheLRU(key)
            cacheQueue.async(flags: .barrier) { [weak self] in
                self?.warmCache[key]?.lastAccessed = Date()
            }
            
            // ⚡️ CRITICAL: Don't seek on looping players - it cancels the looper!
            // Just play if paused
            if cached.player.timeControlStatus != .playing {
                cached.player.play()
            }
            
            AppLogger.debug("WARM cache hit: \(exerciseName)", category: .general)
            return (cached.player, cached.looper)
        }
        
        // 3. Create new player with instant-start optimization
        guard let url = getVideoURL(for: key, videoFilename: videoFilename) else {
            AppLogger.warning("No video URL for: \(exerciseName)", category: .general)
            return nil
        }
        
        AppLogger.debug("Creating player: \(exerciseName)", category: .general)
        
        return createInstantStartPlayerWithLooper(url: url, exerciseName: key, filename: expectedFilename ?? videoFilename ?? "")
    }
    
    /// Get a ready-to-play video player (YouTube-style instant start)
    /// Priority: Hot cache → Warm cache → Create new (with instant-start)
    func getPlayer(for exerciseName: String, videoFilename: String? = nil) -> AVQueuePlayer? {
        let key = exerciseName.lowercased()
        
        // Track as recent
        trackRecentExercise(key)
        
        // Get the correct gender-aware filename we SHOULD be playing
        let expectedFilename = GenderFilterService.shared.getVideoFilename(for: exerciseName, fallbackToOpposite: true)
        
        // 1. Check hot cache first (favorites, current)
        if let cached = hotCache[key] {
            // ✅ VALIDATE: Ensure cached video matches current gender preference
            if let expected = expectedFilename, !expected.isEmpty, cached.filename != expected {
                AppLogger.debug("HOT cache invalid for getPlayer (wrong gender): \(exerciseName), cached: \(cached.filename), expected: \(expected)", category: .general)
                // Remove invalid cache entry and create new player
                hotCache.removeValue(forKey: key)
                guard let url = getVideoURL(for: key, videoFilename: videoFilename) else { return nil }
                return createInstantStartPlayer(url: url, exerciseName: key, filename: expected)
            }
            
            hotCache[key]?.lastAccessed = Date()
            cached.player.seek(to: .zero)
            cached.player.play()
            AppLogger.debug("HOT cache hit for getPlayer: \(exerciseName), looper status: \(cached.looper.status.rawValue)", category: .general)
            return cached.player
        }
        
        // 2. Check warm cache
        if let cached = warmCache[key] {
            // ✅ VALIDATE: Ensure cached video matches current gender preference
            if let expected = expectedFilename, !expected.isEmpty, cached.filename != expected {
                AppLogger.debug("WARM cache invalid for getPlayer (wrong gender): \(exerciseName), cached: \(cached.filename), expected: \(expected)", category: .general)
                // Remove invalid cache entry asynchronously (thread-safe)
                cacheQueue.async(flags: .barrier) { [weak self] in
                    self?.warmCache.removeValue(forKey: key)
                    self?.warmCacheOrder.removeAll { $0 == key }
                }
                guard let url = getVideoURL(for: key, videoFilename: videoFilename) else { return nil }
                return createInstantStartPlayer(url: url, exerciseName: key, filename: expected)
            }
            
            promoteToHotIfFavorite(key)
            cacheQueue.async(flags: .barrier) { [weak self] in
                self?.warmCache[key]?.lastAccessed = Date()
            }
            updateWarmCacheLRU(key)
            cached.player.seek(to: .zero)
            cached.player.play()
            AppLogger.debug("WARM cache hit for getPlayer: \(exerciseName)", category: .general)
            return cached.player
        }
        
        // 3. Create new player with instant-start optimization
        guard let url = getVideoURL(for: key, videoFilename: videoFilename) else {
            AppLogger.warning("No video URL for getPlayer: \(exerciseName)", category: .general)
            return nil
        }
        
        AppLogger.debug("Creating player via getPlayer: \(exerciseName)", category: .general)
        
        return createInstantStartPlayer(url: url, exerciseName: key, filename: expectedFilename ?? videoFilename ?? "")
    }
    
    /// Check if video is ready for instant playback (in cache)
    func isReadyForInstantPlay(exerciseName: String) -> Bool {
        let key = exerciseName.lowercased()
        return hotCache[key] != nil || warmCache[key] != nil
    }
    
    // MARK: - 🎯 Prefetching API
    
    /// ⚡️ MEMORY FIX: DISABLED. Was called by 6+ list views on scroll, creating dozens of AVPlayers
    /// per scroll gesture. Each player leaks ~20-50MB through iOS XPC video processes.
    /// Videos now load on-demand only when user opens ExerciseDetailView.
    func prefetchVisible(exercises: [String]) {
        // NO-OP: Scroll-based prefetching disabled to prevent memory pressure.
        return
    }
    
    /// Call when user is about to tap an exercise (hover/highlight)
    func priorityPrefetch(exerciseName: String) {
        prefetchQueue_bg.async { [weak self] in
            self?.queuePrefetch(exerciseName: exerciseName, priority: .immediate)
            self?.processPrefetchQueue()
        }
    }
    
    /// Call when exercise detail view appears - prefetch adjacent exercises
    func prefetchAdjacent(current: String, previousExercise: String?, nextExercise: String?) {
        prefetchQueue_bg.async { [weak self] in
            if let prev = previousExercise {
                self?.queuePrefetch(exerciseName: prev, priority: .adjacent)
            }
            if let next = nextExercise {
                self?.queuePrefetch(exerciseName: next, priority: .adjacent)
            }
            self?.processPrefetchQueue()
        }
    }
    
    // MARK: - ⭐ Favorites Management
    
    /// Add exercise to favorites (will be cached on next launch)
    func addToFavorites(_ exerciseName: String) {
        let key = exerciseName.lowercased()
        favoriteExercises.insert(key)
        saveFavorites()
        
        // Immediately promote to hot cache if in warm (thread-safe)
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if let cached = self.warmCache.removeValue(forKey: key) {
                var updated = cached
                updated.tier = .hot
                self.hotCache[key] = updated
                self.warmCacheOrder.removeAll { $0 == key }
            }
        }
        
        // Or prefetch if not in cache at all
        if hotCache[key] == nil {
            queuePrefetch(exerciseName: key, priority: .favorite)
            prefetchQueue_bg.async { [weak self] in
                self?.processPrefetchQueue()
            }
        }
    }
    
    /// Remove from favorites
    func removeFromFavorites(_ exerciseName: String) {
        let key = exerciseName.lowercased()
        favoriteExercises.remove(key)
        saveFavorites()
        
        // Demote from hot to warm cache
        if let cached = hotCache.removeValue(forKey: key) {
            var updated = cached
            updated.tier = .warm
            addToWarmCache(key, video: updated)
        }
    }
    
    /// Check if exercise is favorite
    func isFavorite(_ exerciseName: String) -> Bool {
        favoriteExercises.contains(exerciseName.lowercased())
    }
    
    // MARK: - 🧹 Cache Management
    
    /// Clear all caches (call on memory warning)
    func clearAllCaches() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Stop all players
            for cached in self.hotCache.values {
                cached.player.pause()
                cached.player.replaceCurrentItem(with: nil)
            }
            for cached in self.warmCache.values {
                cached.player.pause()
                cached.player.replaceCurrentItem(with: nil)
            }
            
            self.hotCache.removeAll()
            self.warmCache.removeAll()
            self.warmCacheOrder.removeAll()
            
            AppLogger.debug("All video caches cleared", category: .general)
        }
    }
    
    /// Reduce cache (keep only hot tier)
    func reduceCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Clear warm cache with proper cleanup
            for cached in self.warmCache.values {
                self.cleanupPlayer(cached.player, looper: cached.looper)
            }
            self.warmCache.removeAll()
            self.warmCacheOrder.removeAll()
            
            AppLogger.debug("Warm cache cleared, keeping \(self.hotCache.count) hot items", category: .general)
        }
    }
    
    // MARK: - ⚡️ PERFORMANCE: Proper Player Cleanup (prevents memory leaks & invalidation errors)
    
    /// Properly clean up a video player to prevent memory leaks
    /// This prevents the "playerasync_runImmediateCommand signalled err=-12785" errors
    /// ⚡️ ENHANCED: Now uses DispatchQueue to prevent race conditions
    private func cleanupPlayer(_ player: AVQueuePlayer, looper: AVPlayerLooper?) {
        // ⚡️ CRITICAL: Run cleanup on main thread to prevent race conditions
        // AVPlayer operations must be on main thread
        if Thread.isMainThread {
            performPlayerCleanup(player, looper: looper)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performPlayerCleanup(player, looper: looper)
            }
        }
    }
    
    /// Internal player cleanup - must be called on main thread
    private func performPlayerCleanup(_ player: AVQueuePlayer, looper: AVPlayerLooper?) {
        // Stop the looper first (this is critical!)
        looper?.disableLooping()
        
        // Set rate to 0 first to stop playback immediately
        player.rate = 0
        
        // Pause playback
        player.pause()
        
        // Remove all items from the queue
        player.removeAllItems()
        
        // Clear the current item
        // Using a brief delay to allow any pending operations to complete
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.05))
            player.replaceCurrentItem(with: nil)
        }
    }
    
    /// Clear warm cache only (for memory pressure, called by PerformanceOptimizations)
    func clearWarmCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            var clearedCount = 0
            var protectedCount = 0
            
            // Only clear videos that aren't currently playing
            for (key, cached) in self.warmCache {
                // Protect actively playing videos from cache cleanup
                if cached.player.timeControlStatus == .playing {
                    protectedCount += 1
                    AppLogger.debug("Protecting active video from cleanup: \(key)", category: .general)
                    continue
                }
                
                self.cleanupPlayer(cached.player, looper: cached.looper)
                self.warmCache.removeValue(forKey: key)
                clearedCount += 1
            }
            
            // Remove from order list as well
            self.warmCacheOrder = self.warmCacheOrder.filter { self.warmCache.keys.contains($0) }
            
            AppLogger.debug("Cleared \(clearedCount) warm cache entries, protected \(protectedCount) active videos", category: .general)
        }
    }
    
    /// Reduce memory footprint (for memory pressure)
    func reduceMemoryFootprint() {
        // Clear warm cache (protects active videos)
        clearWarmCache()
        
        // Reduce hot cache to just favorites and active videos
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            var keysToRemove: [String] = []
            for (key, cached) in self.hotCache {
                // Protect actively playing videos
                if cached.player.timeControlStatus == .playing {
                    continue
                }
                // Protect favorites
                if self.favoriteExercises.contains(key) {
                    continue
                }
                // Remove non-favorites that aren't playing
                keysToRemove.append(key)
            }
            
            for key in keysToRemove {
                if let cached = self.hotCache.removeValue(forKey: key) {
                    self.cleanupPlayer(cached.player, looper: cached.looper)
                }
            }
            
            AppLogger.debug("Reduced hot cache from \(keysToRemove.count + self.hotCache.count) to \(self.hotCache.count)", category: .general)
        }
    }
    
    /// Pause prefetching (for memory emergency or heavy work)
    func pausePrefetching() {
        prefetchLock.lock()
        prefetchQueue.removeAll()
        activePrefetches.removeAll()
        prefetchLock.unlock()
        
        AppLogger.debug("Video prefetching paused", category: .general)
    }
    
    /// Resume prefetching (after heavy work completes)
    func resumePrefetching() {
        // Don't resume if heavy work is still in progress
        if HeavyWorkSentinel.shared.isHeavyWorkInProgress {
            AppLogger.debug("Prefetch resume skipped - heavy work still in progress", category: .general)
            return
        }
        
        AppLogger.debug("Video prefetching resumed", category: .general)
        
        // Re-warm favorites if needed
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            self?.preWarmFavorites()
        }
    }
    
    // MARK: - Private: Player Creation
    
    /// Create player with looper and return both (prevents looper deallocation)
    private func createInstantStartPlayerWithLooper(url: URL, exerciseName: String, filename: String) -> (player: AVQueuePlayer, looper: AVPlayerLooper)? {
        // Create asset with aggressive streaming options
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,  // Faster load
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4"
        ])
        
        // Create player item optimized for instant start
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        playerItem.preferredForwardBufferDuration = Config.targetBuffer
        
        // Setup looping queue player
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        AppLogger.info("Created AVPlayerLooper for: \(exerciseName), status: \(looper.status.rawValue)", category: .general)
        
        // YouTube-style: Start playing IMMEDIATELY, don't wait for buffer
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        queuePlayer.play()
        AppLogger.debug("Player playing for: \(exerciseName)", category: .general)
        
        // Cache the player
        let cached = CachedVideo(
            player: queuePlayer,
            looper: looper,
            exerciseName: exerciseName,
            filename: filename,
            createdAt: Date(),
            lastAccessed: Date(),
            isBuffered: false,
            tier: favoriteExercises.contains(exerciseName) ? .hot : .warm
        )
        
        if favoriteExercises.contains(exerciseName) {
            addToHotCache(exerciseName, video: cached)
        } else {
            addToWarmCache(exerciseName, video: cached)
        }
        
        return (queuePlayer, looper)
    }
    
    private func createInstantStartPlayer(url: URL, exerciseName: String, filename: String) -> AVQueuePlayer? {
        // Create asset with aggressive streaming options
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,  // Faster load
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4"
        ])
        
        // Create player item optimized for instant start
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        playerItem.preferredForwardBufferDuration = Config.targetBuffer
        
        // Setup looping queue player
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        AppLogger.info("Created AVPlayerLooper via getPlayer for: \(exerciseName), status: \(looper.status.rawValue)", category: .general)
        
        // YouTube-style: Start playing IMMEDIATELY, don't wait for buffer
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        queuePlayer.play()
        AppLogger.debug("Player playing via getPlayer for: \(exerciseName)", category: .general)
        
        // Cache the player
        let cached = CachedVideo(
            player: queuePlayer,
            looper: looper,
            exerciseName: exerciseName,
            filename: filename,
            createdAt: Date(),
            lastAccessed: Date(),
            isBuffered: false,
            tier: favoriteExercises.contains(exerciseName) ? .hot : .warm
        )
        
        if favoriteExercises.contains(exerciseName) {
            addToHotCache(exerciseName, video: cached)
        } else {
            addToWarmCache(exerciseName, video: cached)
        }
        
        return queuePlayer
    }
    
    // MARK: - Private: Cache Operations
    
    private func addToHotCache(_ key: String, video: CachedVideo) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Evict if at capacity (keep only favorites)
            while self.hotCache.count >= Config.hotCacheSize {
                // Find non-favorite to evict
                if let evictKey = self.hotCache.first(where: { !self.favoriteExercises.contains($0.key) })?.key {
                    self.evictFromHot(evictKey)
                } else if let oldest = self.hotCache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key {
                    self.evictFromHot(oldest)
                } else {
                    break
                }
            }
            
            self.hotCache[key] = video
        }
    }
    
    private func addToWarmCache(_ key: String, video: CachedVideo) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Evict LRU if at capacity
            while self.warmCache.count >= Config.warmCacheSize {
                if let oldest = self.warmCacheOrder.first {
                    self.evictFromWarm(oldest)
                } else {
                    break
                }
            }
            
            self.warmCache[key] = video
            self.warmCacheOrder.append(key)
        }
    }
    
    private func updateWarmCacheLRU(_ key: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.warmCacheOrder.removeAll { $0 == key }
            self.warmCacheOrder.append(key)
        }
    }
    
    private func promoteToHotIfFavorite(_ key: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            guard self.favoriteExercises.contains(key), let cached = self.warmCache[key] else { return }
            self.warmCache.removeValue(forKey: key)
            self.warmCacheOrder.removeAll { $0 == key }
            var promoted = cached
            promoted.tier = .hot
            self.hotCache[key] = promoted
        }
    }
    
    private func evictFromHot(_ key: String) {
        if let cached = hotCache.removeValue(forKey: key) {
            // ⚡️ PERFORMANCE: Proper cleanup prevents memory leaks
            // Run on main thread to prevent "invalidated" errors
            DispatchQueue.main.async { [weak self] in
                self?.cleanupPlayer(cached.player, looper: cached.looper)
            }
            AppLogger.debug("Evicted from HOT cache: \(key)", category: .general)
        }
    }
    
    private func evictFromWarm(_ key: String) {
        // Note: This is called from within cacheQueue already
        if let cached = warmCache.removeValue(forKey: key) {
            // ⚡️ PERFORMANCE: Proper cleanup prevents memory leaks
            // Run on main thread to prevent "invalidated" errors
            DispatchQueue.main.async { [weak self] in
                self?.cleanupPlayer(cached.player, looper: cached.looper)
            }
            warmCacheOrder.removeAll { $0 == key }
            AppLogger.debug("Evicted from WARM cache: \(key)", category: .general)
        }
    }
    
    // MARK: - Private: Prefetch Queue
    
    private func queuePrefetch(exerciseName: String, priority: PrefetchJob.Priority) {
        let key = exerciseName.lowercased()
        
        // Skip if already cached or being fetched
        guard hotCache[key] == nil,
              warmCache[key] == nil,
              !activePrefetches.contains(key) else {
            return
        }
        
        // Get video filename
        guard let filename = getVideoFilename(for: key) else {
            return
        }
        
        prefetchLock.lock()
        defer { prefetchLock.unlock() }
        
        // Remove existing lower priority request
        prefetchQueue.removeAll { $0.exerciseName == key }
        
        let job = PrefetchJob(exerciseName: key, filename: filename, priority: priority)
        prefetchQueue.append(job)
        prefetchQueue.sort { $0.priority < $1.priority }
    }
    
    private func processPrefetchQueue() {
        prefetchLock.lock()
        
        // Check concurrent limit
        guard activePrefetches.count < Config.maxConcurrentPrefetch,
              let job = prefetchQueue.first else {
            prefetchLock.unlock()
            return
        }
        
        prefetchQueue.removeFirst()
        activePrefetches.insert(job.exerciseName)
        prefetchLock.unlock()
        
        // Create player on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let urlString = "\(self.r2BaseURL)/\(job.filename)"
            guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else {
                self.prefetchLock.lock()
                self.activePrefetches.remove(job.exerciseName)
                self.prefetchLock.unlock()
                return
            }
            
            // Create optimized player (but don't play yet)
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: false,
                "AVURLAssetOutOfBandMIMETypeKey": "video/mp4"
            ])
            
            let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
            playerItem.preferredForwardBufferDuration = Config.minBufferForPlay
            
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            queuePlayer.automaticallyWaitsToMinimizeStalling = false
            
            // Don't auto-play prefetched videos
            queuePlayer.pause()
            
            let cached = CachedVideo(
                player: queuePlayer,
                looper: looper,
                exerciseName: job.exerciseName,
                filename: job.filename,
                createdAt: Date(),
                lastAccessed: Date(),
                isBuffered: true,
                tier: job.priority == .favorite ? .hot : .warm
            )
            
            if job.priority == .favorite {
                self.addToHotCache(job.exerciseName, video: cached)
            } else {
                self.addToWarmCache(job.exerciseName, video: cached)
            }
            
            self.prefetchLock.lock()
            self.activePrefetches.remove(job.exerciseName)
            self.prefetchLock.unlock()
            
            AppLogger.debug("Prefetched: \(job.exerciseName) (priority: \(job.priority))", category: .general)
            
            // Process next in queue
            self.prefetchQueue_bg.async {
                self.processPrefetchQueue()
            }
        }
    }
    
    // MARK: - Private: Video URL Resolution
    
    private func getVideoURL(for exerciseName: String, videoFilename: String?) -> URL? {
        // 1. ALWAYS check GenderFilterService FIRST for correct gender video
        // This ensures user's gender preference is respected even if videoFilename is provided
        if let filename = GenderFilterService.shared.getVideoFilename(for: exerciseName, fallbackToOpposite: true) {
            let urlString = "\(r2BaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        // 2. Fallback to VideoStreamingService with gender awareness
        if let url = VideoStreamingService.shared.getGenderAwareVideoURL(for: exerciseName) {
            return url
        }
        
        // 3. Check our mapping cache
        let key = exerciseName.lowercased()
        if let filename = videoMappings[key] {
            let urlString = "\(r2BaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        // 4. Last resort: use provided filename if nothing else works
        if let filename = videoFilename, !filename.isEmpty {
            let urlString = "\(r2BaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        return nil
    }
    
    private func getVideoFilename(for exerciseName: String) -> String? {
        let key = exerciseName.lowercased()
        
        // ALWAYS use GenderFilterService for gender-aware video selection
        if let filename = GenderFilterService.shared.getVideoFilename(for: key, fallbackToOpposite: true) {
            return filename
        }
        
        // Fallback to our mapping cache
        if let filename = videoMappings[key] {
            return filename
        }
        
        // Last resort: legacy cache
        return VideoStreamingService.shared.videoFilenameCache[key]
    }
    
    // MARK: - Private: Database Loading
    
    // ⚡️ MEMORY FIX: Removed duplicate Supabase fetch. VideoPlaybackEngine was paginating
    // through ALL 7000+ exercises to build its own videoMappings dictionary, duplicating
    // what VideoStreamingService already does. Now just marks as loaded and relies on
    // getVideoFilename() which already falls back to VideoStreamingService and GenderFilterService.
    private func loadVideoMappingsAsync() {
        VideoStreamingService.shared.$videosLoaded
            .filter { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.mappingsLoaded = true
                AppLogger.debug("VideoPlaybackEngine using VideoStreamingService mappings (no duplicate fetch)", category: .general)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Private: Favorites & Recent Persistence
    
    private func loadFavorites() {
        if let saved = UserDefaults.standard.stringArray(forKey: Config.favoritesKey) {
            favoriteExercises = Set(saved)
        }
    }
    
    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteExercises), forKey: Config.favoritesKey)
    }
    
    /// Sync video favorites with Core Data exercise favorites
    private func syncWithCoreDataFavorites() {
        // Get favorites from Core Data
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let coreDataFavorites = allExercises
            .filter { $0.isFavorite }
            .compactMap { $0.name?.lowercased() }
        
        // Merge with existing video favorites
        var updated = favoriteExercises
        for favorite in coreDataFavorites {
            updated.insert(favorite)
        }
        
        if updated != favoriteExercises {
            favoriteExercises = updated
            saveFavorites()
            
            AppLogger.debug("Synced \(coreDataFavorites.count) Core Data favorites -> \(favoriteExercises.count) total video favorites", category: .general)
        }
    }
    
    private func loadRecentExercises() {
        if let saved = UserDefaults.standard.stringArray(forKey: Config.recentKey) {
            recentExercises = saved
        }
    }
    
    private func trackRecentExercise(_ key: String) {
        recentExercises.removeAll { $0 == key }
        recentExercises.insert(key, at: 0)
        
        // Trim to max
        if recentExercises.count > Config.maxRecentCount {
            recentExercises = Array(recentExercises.prefix(Config.maxRecentCount))
        }
        
        UserDefaults.standard.set(recentExercises, forKey: Config.recentKey)
    }
    
    private func preWarmFavorites() {
        // ⚡️ MEMORY FIX: Limit pre-warming to max 2 favorites (was unlimited).
        // Each pre-warmed player = 20-50MB. Users with 10+ favorites were getting 200MB+ just from pre-warming.
        prefetchLock.lock()
        let shouldSkip = isPreWarmingInProgress || 
            (lastPreWarmTime.map { Date().timeIntervalSince($0) < preWarmCooldown } ?? false)
        if shouldSkip {
            prefetchLock.unlock()
            AppLogger.debug("Skipping duplicate pre-warm (cooldown or in progress)", category: .general)
            return
        }
        isPreWarmingInProgress = true
        prefetchLock.unlock()
        
        guard mappingsLoaded else {
            prefetchLock.lock()
            isPreWarmingInProgress = false
            prefetchLock.unlock()
            // Retry after mappings load
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.0))
                guard !Task.isCancelled else { return }
                self?.preWarmFavorites()
            }
            return
        }
        
        // Skip if heavy work is in progress
        if HeavyWorkSentinel.shared.isHeavyWorkInProgress {
            prefetchLock.lock()
            isPreWarmingInProgress = false
            prefetchLock.unlock()
            AppLogger.debug("Skipping pre-warm - heavy work in progress", category: .general)
            return
        }
        
        // ⚡️ MEMORY FIX: Only pre-warm the 2 most recently used favorites (was ALL favorites)
        let limitedFavorites = Array(favoriteExercises.prefix(2))
        
        AppLogger.debug("Pre-warming \(limitedFavorites.count) of \(favoriteExercises.count) favorites (capped at 2)", category: .general)
        
        for favorite in limitedFavorites {
            queuePrefetch(exerciseName: favorite, priority: .favorite)
        }
        
        prefetchQueue_bg.async { [weak self] in
            self?.processPrefetchQueue()
            
            // Mark pre-warm complete
            self?.prefetchLock.lock()
            self?.isPreWarmingInProgress = false
            self?.lastPreWarmTime = Date()
            self?.prefetchLock.unlock()
        }
    }
    
    // MARK: - Private: System
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            AppLogger.warning("Audio session config failed: \(error.localizedDescription)", category: .general)
        }
    }
    
    private func setupMemoryWarning() {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.reduceCache()
            }
            .store(in: &cancellables)
    }
}

// MARK: - Instant Video Player View (YouTube-style)

struct InstantVideoPlayerView: View {
    let exerciseName: String
    let categoryColor: Color
    var videoFilename: String? = nil
    var onPrefetchAdjacent: ((String?, String?) -> Void)? = nil  // (prev, next) for prefetch
    
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var playerState = InstantVideoPlayerState()
    @State private var hasAppeared = false
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96)
    }
    
    var body: some View {
        ZStack {
            backgroundColor
            
            if let player = playerState.player {
                // Video ready - show immediately
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.animation(.easeIn(duration: 0.15)))
            } else if playerState.isLoading {
                // Brief loading state (should be very quick)
                loadingView
            } else {
                // No video available
                noVideoView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220, maxHeight: 280)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            playerState.loadVideo(exerciseName: exerciseName, videoFilename: videoFilename)
        }
        .onDisappear {
            playerState.pause()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 10) {
            // Pulsing icon (very brief, should rarely be seen)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(categoryColor.opacity(0.6))
        }
    }
    
    private var noVideoView: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundColor(categoryColor.opacity(0.5))
            
            Text("Video Coming Soon")
                .font(.ds_bodySmall).fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Instant Video Player State

class InstantVideoPlayerState: ObservableObject {
    @Published var player: AVQueuePlayer?
    @Published var isLoading = false
    @Published var hasError = false
    
    func loadVideo(exerciseName: String, videoFilename: String?) {
        isLoading = true
        
        // Get player from engine (instant if cached)
        if let queuePlayer = VideoPlaybackEngine.shared.getPlayer(for: exerciseName, videoFilename: videoFilename) {
            DispatchQueue.main.async { [weak self] in
                self?.player = queuePlayer
                self?.isLoading = false
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
                self?.hasError = true
            }
        }
    }
    
    func pause() {
        player?.pause()
    }
    
    func play() {
        player?.play()
    }
}

// MARK: - Preview Helper

#if DEBUG
struct InstantVideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        InstantVideoPlayerView(
            exerciseName: "Barbell Bench Press",
            categoryColor: .red
        )
        .previewLayout(.sizeThatFits)
    }
}
#endif
