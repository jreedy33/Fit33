import Foundation
import AVKit
import Combine
import UIKit

// MARK: - Video Streaming Service
/// Handles fetching exercise videos from Cloudflare R2 with smart prefetching
/// Videos are fetched based on exercise name and user's gender preference
/// Uses YouTube/TikTok-style preloading for instant playback

class VideoStreamingService: ObservableObject {
    static let shared = VideoStreamingService()
    
    // Cloudflare R2 public URL for exercise videos
    private let storageBaseURL = "https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev"
    
    // Cache for video filenames by gender (exercise name -> GenderVideoInfo)
    @Published private(set) var genderVideoCache: [String: GenderVideoInfo] = [:]
    
    // Legacy cache for backwards compatibility
    @Published private(set) var videoFilenameCache: [String: String] = [:]
    @Published private(set) var videoURLCache: [String: URL] = [:] {
        didSet {
            if videoURLCache.count > 100 {
                let sortedKeys = videoURLCache.keys.sorted()
                let keysToRemove = sortedKeys.prefix(videoURLCache.count - 80)
                for key in keysToRemove { videoURLCache.removeValue(forKey: key) }
            }
        }
    }
    
    // Legacy hardcoded video mapping (fallback)
    private let videoMapping: [String: String]
    
    // MARK: - User Gender Preference
    
    enum VideoGender: String, CaseIterable {
        case male = "Male"
        case female = "Female"
        
        var displayName: String { rawValue }
        var folderPath: String {
            switch self {
            case .male: return "Male Workout Videos"
            case .female: return "Female Workout Videos"
            }
        }
    }
    
    /// User's preferred video gender - synced from onboarding/settings
    /// ⚠️ Use GenderFilterService.shared for centralized gender management
    @Published var preferredVideoGender: VideoGender = .male {
        didSet {
            UserDefaults.standard.set(preferredVideoGender.rawValue, forKey: "preferredVideoGender")
            // Clear preloaded players since gender changed
            clearPreloadCache()
            AppLogger.debug("Video gender preference set to: \(preferredVideoGender.rawValue)", category: .general)
        }
    }
    
    /// Structure to hold both male and female video filenames for an exercise
    struct GenderVideoInfo {
        var maleFilename: String?
        var femaleFilename: String?
        
        func filename(for gender: VideoGender) -> String? {
            switch gender {
            case .male: return maleFilename
            case .female: return femaleFilename
            }
        }
        
        func filenameWithFallback(preferred: VideoGender) -> String? {
            // Try preferred gender first, then fall back to opposite
            if let preferred = filename(for: preferred) {
                return preferred
            }
            // Fallback to opposite gender
            let fallback: VideoGender = preferred == .male ? .female : .male
            return filename(for: fallback)
        }
        
        var hasBothGenders: Bool {
            maleFilename != nil && femaleFilename != nil
        }
    }
    
    // 🚀 SMART PREFETCH SYSTEM
    // ⚡️ MEMORY FIX: Reduced from 10 → 3 to prevent ~200MB of idle AVPlayers
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var preloadOrder: [String] = [] // Track order for LRU eviction
    private let maxPreloadedPlayers = 3
    
    // Prefetch queue for background loading
    private let prefetchQueue = DispatchQueue(label: "video.prefetch", qos: .utility)
    private var prefetchingExercises: Set<String> = []
    
    // Loading state
    @Published private(set) var isLoading = false
    @Published private(set) var videosLoaded = false
    
    private var cancellables = Set<AnyCancellable>()
    
    // Local video cache directory (for optional offline mode)
    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("exercise_videos")
    }
    
    private init() {
        // Load legacy mapping as fallback
        self.videoMapping = createExerciseVideoMapping()
        createCacheDirectoryIfNeeded()
        
        // Load user's gender preference
        loadGenderPreference()
        
        // Load video mappings from database (primary source)
        loadVideoMappingsFromDatabase()
        
        // Configure AVPlayer for fast startup
        configureAudioSession()
    }
    
    // MARK: - Gender Preference Management
    
    /// Load gender preference from UserDefaults or user profile
    private func loadGenderPreference() {
        // First check if explicitly set
        if let saved = UserDefaults.standard.string(forKey: "preferredVideoGender"),
           let gender = VideoGender(rawValue: saved) {
            preferredVideoGender = gender
            return
        }
        
        // Fall back to user's profile gender from onboarding
        if let userGender = UserDefaults.standard.string(forKey: "userGender") {
            if userGender.lowercased().contains("female") {
                preferredVideoGender = .female
            } else {
                preferredVideoGender = .male
            }
            // Save to preferredVideoGender key
            UserDefaults.standard.set(preferredVideoGender.rawValue, forKey: "preferredVideoGender")
        }
    }
    
    /// Sync video gender preference from user profile (called after onboarding)
    func syncGenderFromUserProfile() {
        if let userGender = UserDefaults.standard.string(forKey: "userGender") {
            let newGender: VideoGender = userGender.lowercased().contains("female") ? .female : .male
            if preferredVideoGender != newGender {
                preferredVideoGender = newGender
                AppLogger.debug("Synced video gender from profile: \(newGender.rawValue)", category: .general)
            }
        }
    }
    
    /// Set video gender preference (called from settings)
    func setPreferredGender(_ gender: VideoGender) {
        preferredVideoGender = gender
    }
    
    /// Check if exercise has video for both genders
    func hasVideoForBothGenders(exerciseName: String) -> Bool {
        let key = exerciseName.lowercased()
        return genderVideoCache[key]?.hasBothGenders ?? false
    }
    
    // MARK: - Database Video Loading
    
    // Cache for video codes -> filename (for matching by video ID)
    private var videoCodeCache: [String: String] = [:]
    
    /// Load video filenames from Supabase exercises table
    func loadVideoMappingsFromDatabase() {
        Task {
            await fetchVideoFilenamesFromServer()
        }
    }
    
    /// How often video mappings should be re-fetched. They rarely change.
    private static let videoMappingSyncInterval: TimeInterval = 12 * 60 * 60 // 12 hours
    
    private func fetchVideoFilenamesFromServer() async {
        // ⚡️ PERFORMANCE: Skip if we recently fetched video mappings.
        // Video mappings are static data (exercise name → video file) that rarely changes.
        // Fetching 6500+ mappings in 6 paginated calls is expensive on startup.
        let lastFetch = UserDefaults.standard.object(forKey: "lastVideoMappingFetch") as? Date
        let cacheAge = lastFetch.map { Date().timeIntervalSince($0) } ?? .infinity
        
        if !genderVideoCache.isEmpty && cacheAge < Self.videoMappingSyncInterval {
            let hoursAgo = String(format: "%.1f", cacheAge / 3600)
            AppLogger.debug("Skipping video mapping fetch — \(genderVideoCache.count) cached, fetched \(hoursAgo)h ago", category: .general)
            return
        }
        
        do {
            struct VideoMapping: Codable {
                let name: String
                let video_filename: String?
                let video_code: String?
                let gender: String?
            }
            
            // Paginate to fetch ALL exercises (Supabase default limit is 1000)
            var allMappings: [VideoMapping] = []
            let pageSize = 1000
            var offset = 0
            var hasMoreData = true
            
            AppLogger.debug("Starting paginated fetch of video mappings", category: .general)
            
            while hasMoreData {
                let response = try await SupabaseManager.shared.supabaseClient
                    .from("exercises")
                    .select("name, video_filename, video_code, gender")
                    .not("video_filename", operator: .is, value: "null")
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                
                let decoder = JSONDecoder()
                let pageMappings = try decoder.decode([VideoMapping].self, from: response.data)
                allMappings.append(contentsOf: pageMappings)
                
                AppLogger.debug("Fetched \(pageMappings.count) video mappings (total: \(allMappings.count))", category: .general)
                
                if pageMappings.count < pageSize {
                    hasMoreData = false
                } else {
                    offset += pageSize
                }
            }
            
            let mappings = allMappings
            
            // Build caches off main thread to avoid freezing UI
            var newGenderCache: [String: GenderVideoInfo] = [:]
            var newFilenameCache: [String: String] = [:]
            var newCodeCache: [String: String] = [:]
            let preferredGender = await MainActor.run { self.preferredVideoGender }
            
            for mapping in mappings {
                guard let filename = mapping.video_filename, !filename.isEmpty else { continue }
                
                let exerciseKey = mapping.name.lowercased()
                let isMale = mapping.gender?.lowercased() == "male"
                let isFemale = mapping.gender?.lowercased() == "female"
                
                var info = newGenderCache[exerciseKey] ?? GenderVideoInfo()
                
                if isMale {
                    info.maleFilename = filename
                } else if isFemale {
                    info.femaleFilename = filename
                } else {
                    if info.maleFilename == nil { info.maleFilename = filename }
                    if info.femaleFilename == nil { info.femaleFilename = filename }
                }
                
                newGenderCache[exerciseKey] = info
                
                if let preferredFilename = info.filenameWithFallback(preferred: preferredGender) {
                    newFilenameCache[exerciseKey] = preferredFilename
                }
                
                if let code = mapping.video_code, !code.isEmpty {
                    newCodeCache[code] = filename
                }
                
                if let extractedCode = self.extractVideoCode(from: filename) {
                    newCodeCache[extractedCode] = filename
                }
            }
            
            // Assign all caches in one quick main-thread update
            await MainActor.run {
                self.genderVideoCache = newGenderCache
                self.videoFilenameCache = newFilenameCache
                self.videoCodeCache.merge(newCodeCache) { _, new in new }
                self.videosLoaded = true
                
                UserDefaults.standard.set(Date(), forKey: "lastVideoMappingFetch")
                
                AppLogger.info("Loaded \(mappings.count) video mappings from database, \(self.genderVideoCache.count) gender-aware, \(self.genderVideoCache.values.filter { $0.hasBothGenders }.count) with both genders", category: .general)
                
                GenderFilterService.shared.refreshCache()
            }
        } catch {
            AppLogger.warning("Failed to load video mappings from database: \(error.localizedDescription)", category: .general)
            await MainActor.run {
                self.videosLoaded = true
            }
        }
    }
    
    /// Extract video code from filename (e.g., "44171201-Sumo-Squat.mp4" -> "44171201")
    private func extractVideoCode(from filename: String) -> String? {
        let components = filename.components(separatedBy: "-")
        guard let first = components.first, !first.isEmpty else { return nil }
        // Remove any leading zeros for normalization
        return first.trimmingCharacters(in: .whitespaces)
    }
    
    /// Get video URL by video code (direct ID matching)
    func getVideoURL(byVideoCode code: String) -> URL? {
        // First check if we have this code in our cache
        if let filename = videoCodeCache[code] {
            let urlString = "\(storageBaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        // Try with leading zeros removed
        let normalizedCode = code.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        if let filename = videoCodeCache[normalizedCode] {
            let urlString = "\(storageBaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        return nil
    }
    
    // MARK: - Audio Session Configuration
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            AppLogger.warning("Audio session setup failed: \(error.localizedDescription)", category: .general)
        }
    }
    
    // MARK: - 🚀 Smart Prefetch API
    
    /// ⚡️ MEMORY FIX: DISABLED. Was called by multiple views on scroll, creating AVPlayers
    /// for every visible exercise. Each player = 20-50MB through iOS XPC video processes.
    /// Videos now load on-demand via RemoteVideoPlayerView.
    func prefetchVideos(for exerciseNames: [String]) {
        // NO-OP: Scroll-based prefetching disabled to prevent 600MB+ memory usage.
        return
    }
    
    /// Prefetch a single video (call when user hovers/scrolls near an exercise)
    func prefetchVideo(for exerciseName: String) {
        guard !prefetchingExercises.contains(exerciseName),
              preloadedPlayers[exerciseName] == nil,
              let url = getVideoURL(for: exerciseName) else { return }
        
        prefetchingExercises.insert(exerciseName)
        preloadPlayer(for: exerciseName, url: url)
    }
    
    // MARK: - 🏋️ Program-Aware Prefetching
    
    /// Prefetch videos for an active program (today only, limited)
    /// ⚡️ MEMORY FIX: Was prefetching 3 days × ~5 exercises = 15 players (~300MB).
    /// Now only prefetches today's first 3 exercises.
    func prefetchActiveProgramVideos(program: FullCloudProgram, currentDay: Int) {
        prefetchQueue.async { [weak self] in
            guard let self = self else { return }
            
            var exercisesToPrefetch: [String] = []
            
            // Only prefetch today's exercises (was today + next 2 days)
            if let day = program.days.first(where: { $0.day.dayNumber == currentDay }) {
                let exerciseNames = day.exercises.compactMap { $0.exercise.exerciseName }
                exercisesToPrefetch.append(contentsOf: exerciseNames)
            }
            
            // Limit to first 3 (was 15)
            let uniqueExercises = Array(Set(exercisesToPrefetch)).prefix(3)
            
            AppLogger.debug("Prefetching \(uniqueExercises.count) program exercises (day \(currentDay) only)", category: .general)
            
            DispatchQueue.main.async {
                self.prefetchVideos(for: Array(uniqueExercises))
            }
        }
    }
    
    /// Prefetch videos for a specific program day (call when viewing day details)
    func prefetchProgramDay(exercises: [String]) {
        AppLogger.debug("Prefetching \(exercises.count) exercises for program day", category: .general)
        prefetchVideos(for: exercises)
    }
    
    /// Prefetch videos for program preview (limited to save memory)
    /// ⚡️ MEMORY FIX: Was prefetching 3 days × ~5 exercises = 10 players.
    /// Now only prefetches first 2 exercises from day 1.
    func prefetchProgramPreview(program: FullCloudProgram) {
        prefetchQueue.async { [weak self] in
            guard let self = self else { return }
            
            var exercisesToPrefetch: [String] = []
            
            // Only first day, limited exercises (was first 3 days, 10 exercises)
            if let firstDay = program.days.first {
                let exerciseNames = firstDay.exercises.compactMap { $0.exercise.exerciseName }
                exercisesToPrefetch.append(contentsOf: exerciseNames)
            }
            
            let uniqueExercises = Array(Set(exercisesToPrefetch)).prefix(2)
            
            AppLogger.debug("Prefetching \(uniqueExercises.count) exercises for program preview", category: .general)
            
            DispatchQueue.main.async {
                self.prefetchVideos(for: Array(uniqueExercises))
            }
        }
    }
    
    /// Get a pre-buffered player instantly, or create one if not prefetched
    func getPreloadedPlayer(for exerciseName: String) -> AVPlayer? {
        // Check if we have a preloaded player ready
        if let player = preloadedPlayers[exerciseName] {
            // Move to end of LRU (most recently used)
            if let index = preloadOrder.firstIndex(of: exerciseName) {
                preloadOrder.remove(at: index)
                preloadOrder.append(exerciseName)
            }
            AppLogger.debug("Instant playback: \(exerciseName) (preloaded)", category: .general)
            return player
        }
        
        // No preloaded player - create one now
        guard let url = getVideoURL(for: exerciseName) else { return nil }
        
        let player = createOptimizedPlayer(url: url)
        addToCache(exerciseName, player: player)
        AppLogger.debug("Creating player: \(exerciseName)", category: .general)
        return player
    }
    
    // MARK: - Private Preloading Logic
    
    private func preloadPlayer(for exerciseName: String, url: URL) {
        let player = createOptimizedPlayer(url: url)
        
        // Start buffering immediately
        player.currentItem?.preferredForwardBufferDuration = 2 // Buffer 2 seconds (was 5 — saves ~3s of video RAM per player)
        
        addToCache(exerciseName, player: player)
        prefetchingExercises.remove(exerciseName)
        
        AppLogger.debug("Prefetched video: \(exerciseName)", category: .general)
    }
    
    private func createOptimizedPlayer(url: URL) -> AVPlayer {
        // Create asset with optimized loading
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false, // Faster loading
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4"
        ])
        
        // Load only essential keys for fast startup
        let keys = ["playable", "duration"]
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: keys)
        
        // Optimize for streaming — reduced buffer to save memory
        playerItem.preferredForwardBufferDuration = 2 // Buffer 2 seconds ahead (was 3)
        
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false // Start playing ASAP
        
        return player
    }
    
    private func addToCache(_ exerciseName: String, player: AVPlayer) {
        // LRU eviction if at capacity
        if preloadedPlayers.count >= maxPreloadedPlayers, let oldest = preloadOrder.first {
            preloadedPlayers[oldest]?.pause()
            preloadedPlayers[oldest] = nil
            preloadOrder.removeFirst()
            AppLogger.debug("Evicted from video cache: \(oldest)", category: .general)
        }
        
        preloadedPlayers[exerciseName] = player
        preloadOrder.append(exerciseName)
    }
    
    /// Clear all preloaded players (call on memory warning)
    func clearPreloadCache() {
        for player in preloadedPlayers.values {
            player.pause()
            player.replaceCurrentItem(with: nil)  // ⚡️ MEMORY FIX: Release the AVPlayerItem to free video buffers
        }
        preloadedPlayers.removeAll()
        preloadOrder.removeAll()
        prefetchingExercises.removeAll()
        AppLogger.debug("Cleared prefetch cache", category: .general)
    }
    
    // MARK: - Public Methods
    
    /// Get video URL for an exercise (remote streaming or cached)
    /// Priority: 1. Local cache, 2. Database mapping (R2), 3. Legacy hardcoded mapping
    /// Get video URL for exercise using user's preferred gender (with automatic fallback)
    func getVideoURL(for exerciseName: String) -> URL? {
        return getVideoURL(for: exerciseName, gender: preferredVideoGender)
    }
    
    /// Get video URL for exercise with specific gender preference
    /// Automatically falls back to opposite gender if preferred not available
    func getVideoURL(for exerciseName: String, gender: VideoGender) -> URL? {
        let startTime = Date()
        
        // First check local cache
        if let cachedURL = getLocalCachedVideo(for: exerciseName) {
            SessionLogManager.shared.log(.debug, category: .data, message: "Video from cache: \(exerciseName)", metadata: [
                "source": "local_cache",
                "load_time_ms": Int(Date().timeIntervalSince(startTime) * 1000)
            ])
            return cachedURL
        }
        
        let normalizedName = exerciseName.lowercased().trimmingCharacters(in: .whitespaces)
        
        // 🆕 PRIMARY: Check gender-aware cache with fallback
        if let genderInfo = genderVideoCache[normalizedName] {
            if let filename = genderInfo.filenameWithFallback(preferred: gender) {
                let urlString = "\(storageBaseURL)/\(filename)"
                if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                    let usedFallback = genderInfo.filename(for: gender) == nil
                    let genderUsed = usedFallback ? (gender == .male ? "Female" : "Male") : gender.rawValue
                    SessionLogManager.shared.log(.debug, category: .data, message: "Video URL: \(exerciseName)", metadata: [
                        "gender": genderUsed,
                        "fallback": usedFallback,
                        "source": "r2_gender_cache",
                        "load_time_ms": Int(Date().timeIntervalSince(startTime) * 1000)
                    ])
                    AppLogger.debug("\(genderUsed) video: \(exerciseName) -> \(filename)", category: .general)
                    return url
                }
            }
        }
        
        // Try legacy cache
        if let filename = videoFilenameCache[normalizedName] {
            let urlString = "\(storageBaseURL)/\(filename)"
            if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                AppLogger.debug("R2 video: \(exerciseName) -> \(filename)", category: .general)
                return url
            }
        }
        
        // Try exact match on database cache with original name
        if let filename = videoFilenameCache[exerciseName] {
            let urlString = "\(storageBaseURL)/\(filename)"
            if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                AppLogger.debug("R2 video (exact): \(exerciseName) -> \(filename)", category: .general)
                return url
            }
        }
        
        // FALLBACK: Check legacy hardcoded mapping
        if let filename = videoMapping[exerciseName] {
            let urlString = "\(storageBaseURL)/\(filename)"
            if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                AppLogger.debug("Legacy video mapping: \(exerciseName) -> \(filename)", category: .general)
                return url
            }
        }
        
        // Try fuzzy match on legacy hardcoded mapping
        for (key, filename) in videoMapping {
            if key.lowercased() == normalizedName {
                let urlString = "\(storageBaseURL)/\(filename)"
                if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                    AppLogger.debug("Legacy fuzzy video mapping: \(exerciseName) -> \(filename)", category: .general)
                    return url
                }
            }
        }
        
        AppLogger.warning("No video mapping found for: \(exerciseName)", category: .general)
        return nil
    }
    
    /// Get video URL for a specific exercise with gender preference
    /// ALWAYS uses gender-aware lookup first, then falls back to provided filename
    func getVideoURL(for exerciseName: String, videoFilename: String?) -> URL? {
        // First check local cache
        if let cachedURL = getLocalCachedVideo(for: exerciseName) {
            return cachedURL
        }
        
        // ALWAYS try gender-aware lookup FIRST to respect user's gender preference
        // This ensures male users see male videos and female users see female videos
        if let url = getVideoURL(for: exerciseName) {
            return url
        }
        
        // Last resort: use provided filename if gender-aware lookup fails
        if let filename = videoFilename, !filename.isEmpty {
            let urlString = "\(storageBaseURL)/\(filename)"
            if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                AppLogger.debug("Fallback to direct filename: \(exerciseName) -> \(filename)", category: .general)
                return url
            }
        }
        
        return nil
    }
    
    /// Get streaming URL (always remote, good for preview)
    func getStreamingURL(for exerciseName: String) -> URL? {
        let normalizedName = exerciseName.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Check database cache first
        if let filename = videoFilenameCache[normalizedName] {
            let urlString = "\(storageBaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        
        // Fall back to legacy mapping
        if let filename = videoMapping[exerciseName] {
            let urlString = "\(storageBaseURL)/\(filename)"
            return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
        }
        return nil
    }
    
    /// Download video for offline use
    func downloadVideo(for exerciseName: String) async -> Bool {
        guard let filename = videoMapping[exerciseName],
              let remoteURL = getStreamingURL(for: exerciseName),
              let cacheDir = cacheDirectory else {
            return false
        }
        
        let localURL = cacheDir.appendingPathComponent(filename)
        
        // Skip if already cached
        if FileManager.default.fileExists(atPath: localURL.path) {
            return true
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: localURL)
            AppLogger.info("Cached video: \(exerciseName)", category: .general)
            return true
        } catch {
            AppLogger.error("Failed to cache video: \(error.localizedDescription)", category: .general)
            return false
        }
    }
    
    /// Clear video cache to free up space
    func clearCache() {
        guard let cacheDir = cacheDirectory else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            AppLogger.info("Video cache cleared", category: .general)
        } catch {
            AppLogger.error("Failed to clear video cache: \(error.localizedDescription)", category: .general)
        }
    }
    
    /// Get cache size in bytes
    func getCacheSize() -> Int64 {
        guard let cacheDir = cacheDirectory else { return 0 }
        
        var totalSize: Int64 = 0
        
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        return totalSize
    }
    
    // MARK: - Private Methods
    
    private func createCacheDirectoryIfNeeded() {
        guard let cacheDir = cacheDirectory else { return }
        
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }
    
    // Old loadVideoMappings removed - now using loadVideoMappingsFromDatabase()
    
    private func getLocalCachedVideo(for exerciseName: String) -> URL? {
        guard let cacheDir = cacheDirectory,
              let filename = videoMapping[exerciseName] else { return nil }
        
        let localURL = cacheDir.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        
        return nil
    }
}

// MARK: - Supporting Types

private struct ExerciseVideoMapping: Codable {
    let exercise_name: String
    let video_url: String
}

// MARK: - Video Player Without Controls

struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .white
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        
        view.playerLayer = playerLayer
        
        return view
    }
    
    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        // Frame will be updated in layoutSubviews
    }
    
    class PlayerContainerView: UIView {
        var playerLayer: AVPlayerLayer?
        
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
        }
    }
}

// MARK: - Remote Video Player View (YouTube-Style Instant Start)

import SwiftUI

struct RemoteVideoPlayerView: View {
    let exerciseName: String
    let categoryColor: Color
    var videoFilename: String? = nil  // Direct video filename from Exercise entity
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject private var playerManager = RemoteVideoPlayerManager()
    @State private var hasAppeared = false
    @State private var showPlayer = false
    @State private var posterImage: UIImage?  // 🖼️ YouTube-style poster frame
    
    private var backgroundColor: Color {
        .white // Pure white to match exercise video content backgrounds
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            backgroundColor
            
            if let player = playerManager.player, showPlayer {
                VideoPlayerLayerView(player: player)
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.animation(.easeIn(duration: 0.15)))
            } else if let poster = posterImage {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if !playerManager.isLoading, playerManager.player == nil {
                // 🚫 No video available
                VStack(spacing: 14) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 64))
                        .foregroundColor(categoryColor.opacity(0.4))
                    
                    Text("Video Coming Soon")
                        .font(.ds_bodySmall).fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            
            posterImage = VideoThumbnailService.shared.getPosterFrame(for: exerciseName)
            playerManager.loadVideo(for: exerciseName, videoFilename: videoFilename)
        }
        .onReceive(playerManager.$isReadyToDisplay) { ready in
            guard ready, !showPlayer else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                showPlayer = true
            }
        }
        .onDisappear {
            playerManager.pause()
        }
        // 🖼️ Auto-capture poster frame when video finishes loading
        .onReceive(playerManager.$isLoading) { isLoading in
            // When loading transitions from true → false and we have a player, capture the poster
            if !isLoading, let player = playerManager.player {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.8))
                    VideoThumbnailService.shared.capturePosterFrame(from: player, exerciseName: exerciseName)
                }
            }
        }
        .task {
            // Periodic check to ensure looping stays active while view is visible
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Every 10 seconds
                if playerManager.player?.timeControlStatus == .paused {
                    playerManager.ensureLooping()
                }
            }
        }
    }
}

// MARK: - Remote Video Player Manager (YouTube-Style Engine)

class RemoteVideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var isReadyToDisplay = false
    @Published var error: Error?
    
    var queuePlayer: AVQueuePlayer?
    var playerLooper: AVPlayerLooper?
    private var readinessCancellable: AnyCancellable?
    
    func loadVideo(for exerciseName: String, videoFilename: String? = nil) {
        isLoading = true
        isReadyToDisplay = false
        hasRetriedLooper = false
        
        let genderAwareFilename = GenderFilterService.shared.getVideoFilename(for: exerciseName, fallbackToOpposite: true) ?? videoFilename
        
        if let playerWithLooper = VideoPlaybackEngine.shared.getPlayerWithLooper(for: exerciseName, videoFilename: genderAwareFilename) {
            DispatchQueue.main.async { [weak self] in
                self?.queuePlayer = playerWithLooper.player
                self?.player = playerWithLooper.player
                self?.playerLooper = playerWithLooper.looper
                self?.hasRetriedLooper = false
                self?.isLoading = false
                self?.observePlayerReadiness(playerWithLooper.player)
                
                let cacheStatus = VideoPlaybackEngine.shared.isReadyForInstantPlay(exerciseName: exerciseName) ? "cached" : "new"
                let genderMatch = GenderFilterService.shared.hasPreferredGenderVideo(for: exerciseName) ? "preferred" : "fallback"
                AppLogger.debug("Video ready (\(cacheStatus), \(genderMatch) gender, looper: active): \(exerciseName)", category: .general)
            }
            return
        }
        
        if let preloadedPlayer = VideoStreamingService.shared.getPreloadedPlayer(for: exerciseName) {
            setupLegacyPlayer(from: preloadedPlayer, exerciseName: exerciseName)
            isLoading = false
            return
        }
        
        if let filename = genderAwareFilename, !filename.isEmpty {
            let storageBaseURL = "https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev"
            let urlString = "\(storageBaseURL)/\(filename)"
            if let videoURL = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                createDirectPlayer(url: videoURL, exerciseName: exerciseName)
                return
            }
        }
        
        if let videoURL = VideoStreamingService.shared.getGenderAwareVideoURL(for: exerciseName) {
            createDirectPlayer(url: videoURL, exerciseName: exerciseName)
            return
        }
        
        AppLogger.warning("No video found for: \(exerciseName)", category: .general)
        isLoading = false
    }
    
    private func observePlayerReadiness(_ player: AVPlayer) {
        readinessCancellable?.cancel()
        
        if player.currentItem?.status == .readyToPlay {
            isReadyToDisplay = true
            return
        }
        
        readinessCancellable = player.currentItem?.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isReadyToDisplay = true
            }
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled, let self = self, !self.isReadyToDisplay else { return }
            self.isReadyToDisplay = true
        }
    }
    
    private func createDirectPlayer(url: URL, exerciseName: String) {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4"
        ])
        
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        playerItem.preferredForwardBufferDuration = 2
        
        let qp = AVQueuePlayer(playerItem: playerItem)
        self.playerLooper = AVPlayerLooper(player: qp, templateItem: playerItem)
        
        qp.automaticallyWaitsToMinimizeStalling = false
        qp.play()
        
        self.queuePlayer = qp
        self.player = qp
        self.isLoading = false
        observePlayerReadiness(qp)
    }
    
    private func setupLegacyPlayer(from sourcePlayer: AVPlayer, exerciseName: String) {
        guard let currentItem = sourcePlayer.currentItem else { return }
        
        let asset = currentItem.asset
        let loopItem = AVPlayerItem(asset: asset)
        loopItem.preferredForwardBufferDuration = 3
        
        let qp = AVQueuePlayer(playerItem: loopItem)
        self.playerLooper = AVPlayerLooper(player: qp, templateItem: loopItem)
        
        self.queuePlayer = qp
        self.player = qp
        qp.play()
        observePlayerReadiness(qp)
    }
    
    func pause() {
        player?.pause()
    }
    
    func play() {
        // Ensure player plays and looper is still active
        if let looper = playerLooper, looper.status != .ready {
            AppLogger.warning("Video looper not ready, recreating", category: .general)
            // Looper might have failed, recreate it
            if let qp = queuePlayer, let currentItem = qp.currentItem {
                self.playerLooper = AVPlayerLooper(player: qp, templateItem: currentItem)
            }
        }
        player?.play()
    }
    
    private var hasRetriedLooper = false
    
    func ensureLooping() {
        // Simple check: if video is paused and has content, restart it
        guard let qp = queuePlayer,
              qp.currentItem != nil,
              qp.timeControlStatus == .paused else { return }
        
        // If no looper and we haven't tried yet, create one
        if playerLooper == nil && !hasRetriedLooper {
            AppLogger.debug("Creating looper for continuous playback", category: .general)
            if let currentItem = qp.currentItem {
                self.playerLooper = AVPlayerLooper(player: qp, templateItem: currentItem)
                hasRetriedLooper = true
            }
        }
        
        // Always try to play if paused
        qp.play()
    }
    
    deinit {
        readinessCancellable?.cancel()
        pause()
    }
}

