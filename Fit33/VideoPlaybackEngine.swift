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
    private struct Config {
        // Cache tiers
        static let hotCacheSize = 5          // Favorites + current (always in RAM)
        static let warmCacheSize = 15        // Recently viewed (LRU eviction)
        static let maxTotalPlayers = 20      // Total players in memory
        
        // Buffering
        static let minBufferForPlay: TimeInterval = 0.3    // Start playing after 300ms buffer
        static let targetBuffer: TimeInterval = 3.0         // Target 3s ahead
        static let maxBuffer: TimeInterval = 8.0            // Don't buffer more than 8s
        
        // Prefetch
        static let prefetchRadius = 3        // Prefetch 3 exercises around current
        static let maxConcurrentPrefetch = 2 // Max concurrent network requests
        
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
    
    // MARK: - Queues
    private let cacheQueue = DispatchQueue(label: "video.cache", qos: .userInitiated)
    private let prefetchQueue_bg = DispatchQueue(label: "video.prefetch", qos: .utility)
    private let mappingQueue = DispatchQueue(label: "video.mapping", qos: .background)
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Types
    
    private struct CachedVideo {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
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
        
        #if DEBUG
        print("🎬 VideoPlaybackEngine initialized")
        #endif
    }
    
    // MARK: - 🚀 PUBLIC API: Get Instant Player
    
    /// Get a ready-to-play video player (YouTube-style instant start)
    /// Priority: Hot cache → Warm cache → Create new (with instant-start)
    func getPlayer(for exerciseName: String, videoFilename: String? = nil) -> AVQueuePlayer? {
        let key = exerciseName.lowercased()
        
        // Track as recent
        trackRecentExercise(key)
        
        // 1. Check hot cache first (favorites, current)
        if let cached = hotCache[key] {
            hotCache[key]?.lastAccessed = Date()
            cached.player.seek(to: .zero)
            cached.player.play()
            #if DEBUG
            print("⚡ HOT cache hit: \(exerciseName)")
            #endif
            return cached.player
        }
        
        // 2. Check warm cache
        if let cached = warmCache[key] {
            promoteToHotIfFavorite(key)
            warmCache[key]?.lastAccessed = Date()
            updateWarmCacheLRU(key)
            cached.player.seek(to: .zero)
            cached.player.play()
            #if DEBUG
            print("🌡️ WARM cache hit: \(exerciseName)")
            #endif
            return cached.player
        }
        
        // 3. Create new player with instant-start optimization
        guard let url = getVideoURL(for: key, videoFilename: videoFilename) else {
            #if DEBUG
            print("❌ No video URL for: \(exerciseName)")
            #endif
            return nil
        }
        
        #if DEBUG
        print("🆕 Creating player: \(exerciseName)")
        #endif
        
        return createInstantStartPlayer(url: url, exerciseName: key, filename: videoFilename ?? "")
    }
    
    /// Check if video is ready for instant playback (in cache)
    func isReadyForInstantPlay(exerciseName: String) -> Bool {
        let key = exerciseName.lowercased()
        return hotCache[key] != nil || warmCache[key] != nil
    }
    
    // MARK: - 🎯 Prefetching API
    
    /// Call when user views exercise list - prefetch visible items
    func prefetchVisible(exercises: [String]) {
        prefetchQueue_bg.async { [weak self] in
            guard let self = self else { return }
            
            for (index, name) in exercises.prefix(Config.prefetchRadius).enumerated() {
                let priority: PrefetchJob.Priority = index == 0 ? .immediate : .adjacent
                self.queuePrefetch(exerciseName: name, priority: priority)
            }
            
            self.processPrefetchQueue()
        }
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
        
        // Immediately promote to hot cache if in warm
        if let cached = warmCache.removeValue(forKey: key) {
            var updated = cached
            updated.tier = .hot
            hotCache[key] = updated
            warmCacheOrder.removeAll { $0 == key }
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
            
            #if DEBUG
            print("🧹 All video caches cleared")
            #endif
        }
    }
    
    /// Reduce cache (keep only hot tier)
    func reduceCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Clear warm cache
            for cached in self.warmCache.values {
                cached.player.pause()
                cached.player.replaceCurrentItem(with: nil)
            }
            self.warmCache.removeAll()
            self.warmCacheOrder.removeAll()
            
            #if DEBUG
            print("📉 Warm cache cleared, keeping \(self.hotCache.count) hot items")
            #endif
        }
    }
    
    // MARK: - Private: Player Creation
    
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
        
        // YouTube-style: Start playing IMMEDIATELY, don't wait for buffer
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        queuePlayer.play()
        
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
        warmCacheOrder.removeAll { $0 == key }
        warmCacheOrder.append(key)
    }
    
    private func promoteToHotIfFavorite(_ key: String) {
        guard favoriteExercises.contains(key), let cached = warmCache[key] else { return }
        warmCache.removeValue(forKey: key)
        warmCacheOrder.removeAll { $0 == key }
        var promoted = cached
        promoted.tier = .hot
        hotCache[key] = promoted
    }
    
    private func evictFromHot(_ key: String) {
        if let cached = hotCache.removeValue(forKey: key) {
            cached.player.pause()
            cached.player.replaceCurrentItem(with: nil)
            #if DEBUG
            print("🗑️ Evicted from HOT: \(key)")
            #endif
        }
    }
    
    private func evictFromWarm(_ key: String) {
        if let cached = warmCache.removeValue(forKey: key) {
            cached.player.pause()
            cached.player.replaceCurrentItem(with: nil)
            warmCacheOrder.removeAll { $0 == key }
            #if DEBUG
            print("🗑️ Evicted from WARM: \(key)")
            #endif
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
            
            #if DEBUG
            print("📥 Prefetched: \(job.exerciseName) (priority: \(job.priority))")
            #endif
            
            // Process next in queue
            self.prefetchQueue_bg.async {
                self.processPrefetchQueue()
            }
        }
    }
    
    // MARK: - Private: Video URL Resolution
    
    private func getVideoURL(for exerciseName: String, videoFilename: String?) -> URL? {
        // 1. Direct filename if provided (already gender-specific from database)
        if let filename = videoFilename, !filename.isEmpty {
            let urlString = "\(r2BaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        // 2. Use GenderFilterService for gender-aware video selection
        if let filename = GenderFilterService.shared.getVideoFilename(for: exerciseName, fallbackToOpposite: true) {
            let urlString = "\(r2BaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        // 3. Check our mapping cache
        let key = exerciseName.lowercased()
        if let filename = videoMappings[key] {
            let urlString = "\(r2BaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        // 4. Fallback to VideoStreamingService with gender awareness
        return VideoStreamingService.shared.getGenderAwareVideoURL(for: exerciseName)
    }
    
    private func getVideoFilename(for exerciseName: String) -> String? {
        let key = exerciseName.lowercased()
        
        if let filename = videoMappings[key] {
            return filename
        }
        
        return VideoStreamingService.shared.videoFilenameCache[key]
    }
    
    // MARK: - Private: Database Loading
    
    private func loadVideoMappingsAsync() {
        mappingQueue.async { [weak self] in
            Task {
                await self?.fetchVideoMappings()
            }
        }
    }
    
    private func fetchVideoMappings() async {
        do {
            struct VideoMapping: Codable {
                let name: String
                let video_filename: String?
            }
            
            var allMappings: [VideoMapping] = []
            let pageSize = 1000
            var offset = 0
            var hasMore = true
            
            while hasMore {
                let response = try await SupabaseManager.shared.supabaseClient
                    .from("exercises")
                    .select("name, video_filename")
                    .not("video_filename", operator: .is, value: "null")
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                
                let pageMappings = try JSONDecoder().decode([VideoMapping].self, from: response.data)
                allMappings.append(contentsOf: pageMappings)
                
                hasMore = pageMappings.count == pageSize
                offset += pageSize
            }
            
            await MainActor.run { [weak self] in
                for mapping in allMappings {
                    if let filename = mapping.video_filename, !filename.isEmpty {
                        self?.videoMappings[mapping.name.lowercased()] = filename
                    }
                }
                self?.mappingsLoaded = true
                
                #if DEBUG
                print("🎬 Loaded \(allMappings.count) video mappings")
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ Failed to load video mappings: \(error)")
            #endif
        }
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
            
            #if DEBUG
            print("🔄 Synced \(coreDataFavorites.count) Core Data favorites -> \(favoriteExercises.count) total video favorites")
            #endif
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
        guard mappingsLoaded else {
            // Retry after mappings load
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.preWarmFavorites()
            }
            return
        }
        
        #if DEBUG
        print("🔥 Pre-warming \(favoriteExercises.count) favorites...")
        #endif
        
        for favorite in favoriteExercises {
            queuePrefetch(exerciseName: favorite, priority: .favorite)
        }
        
        prefetchQueue_bg.async { [weak self] in
            self?.processPrefetchQueue()
        }
    }
    
    // MARK: - Private: System
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            #if DEBUG
            print("⚠️ Audio session config failed: \(error)")
            #endif
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
                .font(.system(size: 14, weight: .medium))
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
