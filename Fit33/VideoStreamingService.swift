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
    @Published private(set) var videoURLCache: [String: URL] = [:]
    
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
            #if DEBUG
            print("📹 Video gender preference set to: \(preferredVideoGender.rawValue)")
            #endif
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
    // In-memory cache of pre-buffered players (LRU - keeps last 10)
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var preloadOrder: [String] = [] // Track order for LRU eviction
    private let maxPreloadedPlayers = 10
    
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
                #if DEBUG
                print("📹 Synced video gender from profile: \(newGender.rawValue)")
                #endif
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
    
    private func fetchVideoFilenamesFromServer() async {
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
            
            #if DEBUG
            print("📹 [VIDEO] Starting paginated fetch of video mappings...")
            #endif
            
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
                
                #if DEBUG
                print("📹 [VIDEO] Fetched \(pageMappings.count) mappings (total: \(allMappings.count))")
                #endif
                
                if pageMappings.count < pageSize {
                    hasMoreData = false
                } else {
                    offset += pageSize
                }
            }
            
            let mappings = allMappings
            
            await MainActor.run {
                // Build gender-aware cache
                for mapping in mappings {
                    guard let filename = mapping.video_filename, !filename.isEmpty else { continue }
                    
                    let exerciseKey = mapping.name.lowercased()
                    let isMale = mapping.gender?.lowercased() == "male"
                    let isFemale = mapping.gender?.lowercased() == "female"
                    
                    // Get or create gender info
                    var info = self.genderVideoCache[exerciseKey] ?? GenderVideoInfo()
                    
                    if isMale {
                        info.maleFilename = filename
                    } else if isFemale {
                        info.femaleFilename = filename
                    } else {
                        // No gender specified - use as default for both
                        if info.maleFilename == nil { info.maleFilename = filename }
                        if info.femaleFilename == nil { info.femaleFilename = filename }
                    }
                    
                    self.genderVideoCache[exerciseKey] = info
                    
                    // Also keep legacy cache (using preferred gender)
                    if let preferredFilename = info.filenameWithFallback(preferred: self.preferredVideoGender) {
                        self.videoFilenameCache[exerciseKey] = preferredFilename
                    }
                    
                    // Cache by video code
                    if let code = mapping.video_code, !code.isEmpty {
                        self.videoCodeCache[code] = filename
                    }
                    
                    if let extractedCode = self.extractVideoCode(from: filename) {
                        self.videoCodeCache[extractedCode] = filename
                    }
                }
                
                self.videosLoaded = true
                #if DEBUG
                print("📹 Loaded \(mappings.count) video mappings from database")
                print("📹 Gender-aware cache has \(self.genderVideoCache.count) exercises")
                let bothGenders = self.genderVideoCache.values.filter { $0.hasBothGenders }.count
                print("📹 \(bothGenders) exercises have both male & female videos")
                #endif
                
                // 🔄 Refresh GenderFilterService cache now that we have video mappings
                GenderFilterService.shared.refreshCache()
            }
        } catch {
            print("⚠️ Failed to load video mappings from database: \(error)")
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
            print("⚠️ Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - 🚀 Smart Prefetch API
    
    /// Call this when exercises become visible (e.g., in a list)
    /// Prefetches videos in background for instant playback
    func prefetchVideos(for exerciseNames: [String]) {
        let prefetchCount = min(exerciseNames.count, 5)
        SessionLogManager.shared.log(.debug, category: .data, message: "Video prefetch started", metadata: [
            "requested": exerciseNames.count,
            "prefetching": prefetchCount
        ])
        
        prefetchQueue.async { [weak self] in
            guard let self = self else { return }
            var prefetched = 0
            
            for name in exerciseNames.prefix(5) { // Prefetch up to 5 at a time
                guard !self.prefetchingExercises.contains(name),
                      self.preloadedPlayers[name] == nil,
                      let url = self.getVideoURL(for: name) else { continue }
                
                self.prefetchingExercises.insert(name)
                prefetched += 1
                
                DispatchQueue.main.async {
                    self.preloadPlayer(for: name, url: url)
                }
            }
            
            if prefetched > 0 {
                SessionLogManager.shared.log(.debug, category: .data, message: "Videos prefetching", metadata: [
                    "count": prefetched
                ])
            }
        }
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
    
    /// Prefetch videos for an active program (today + next 2 days)
    /// Call this when app launches with an active program or when program is started
    func prefetchActiveProgramVideos(program: FullCloudProgram, currentDay: Int) {
        prefetchQueue.async { [weak self] in
            guard let self = self else { return }
            
            var exercisesToPrefetch: [String] = []
            
            // Get exercises for today and next 2 days
            let daysToPreload = [currentDay, currentDay + 1, currentDay + 2]
            
            for dayNumber in daysToPreload {
                if let day = program.days.first(where: { $0.day.dayNumber == dayNumber }) {
                    let exerciseNames = day.exercises.compactMap { $0.exercise.exerciseName }
                    exercisesToPrefetch.append(contentsOf: exerciseNames)
                }
            }
            
            // Remove duplicates and limit to first 15
            let uniqueExercises = Array(Set(exercisesToPrefetch)).prefix(15)
            
            print("🏋️ Prefetching \(uniqueExercises.count) program exercises (days \(daysToPreload))")
            
            DispatchQueue.main.async {
                self.prefetchVideos(for: Array(uniqueExercises))
            }
        }
    }
    
    /// Prefetch videos for a specific program day (call when viewing day details)
    func prefetchProgramDay(exercises: [String]) {
        print("📅 Prefetching \(exercises.count) exercises for program day")
        prefetchVideos(for: exercises)
    }
    
    /// Prefetch videos for program preview (first few days when user views program details)
    func prefetchProgramPreview(program: FullCloudProgram) {
        prefetchQueue.async { [weak self] in
            guard let self = self else { return }
            
            var exercisesToPrefetch: [String] = []
            
            // Get exercises from first 3 days for preview
            for day in program.days.prefix(3) {
                let exerciseNames = day.exercises.compactMap { $0.exercise.exerciseName }
                exercisesToPrefetch.append(contentsOf: exerciseNames)
            }
            
            let uniqueExercises = Array(Set(exercisesToPrefetch)).prefix(10)
            
            print("👀 Prefetching \(uniqueExercises.count) exercises for program preview")
            
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
            #if DEBUG
            print("⚡ Instant playback: \(exerciseName) (preloaded)")
            #endif
            return player
        }
        
        // No preloaded player - create one now
        guard let url = getVideoURL(for: exerciseName) else { return nil }
        
        let player = createOptimizedPlayer(url: url)
        addToCache(exerciseName, player: player)
        #if DEBUG
        print("🎬 Creating player: \(exerciseName)")
        #endif
        return player
    }
    
    // MARK: - Private Preloading Logic
    
    private func preloadPlayer(for exerciseName: String, url: URL) {
        let player = createOptimizedPlayer(url: url)
        
        // Start buffering immediately
        player.currentItem?.preferredForwardBufferDuration = 5 // Buffer 5 seconds
        
        addToCache(exerciseName, player: player)
        prefetchingExercises.remove(exerciseName)
        
        #if DEBUG
        print("📥 Prefetched: \(exerciseName)")
        #endif
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
        
        // Optimize for streaming
        playerItem.preferredForwardBufferDuration = 3 // Buffer 3 seconds ahead
        
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
            #if DEBUG
            print("🗑️ Evicted from cache: \(oldest)")
            #endif
        }
        
        preloadedPlayers[exerciseName] = player
        preloadOrder.append(exerciseName)
    }
    
    /// Clear all preloaded players (call on memory warning)
    func clearPreloadCache() {
        for player in preloadedPlayers.values {
            player.pause()
        }
        preloadedPlayers.removeAll()
        preloadOrder.removeAll()
        prefetchingExercises.removeAll()
        #if DEBUG
        print("🧹 Cleared prefetch cache")
        #endif
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
                    #if DEBUG
                    print("📹 \(genderUsed) video: \(exerciseName) -> \(filename)")
                    #endif
                    return url
                }
            }
        }
        
        // Try legacy cache
        if let filename = videoFilenameCache[normalizedName] {
            let urlString = "\(storageBaseURL)/\(filename)"
            if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                #if DEBUG
                print("📹 R2 video: \(exerciseName) -> \(filename)")
                #endif
                return url
            }
        }
        
        // Try exact match on database cache with original name
        if let filename = videoFilenameCache[exerciseName] {
            let urlString = "\(storageBaseURL)/\(filename)"
            if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                #if DEBUG
                print("📹 R2 video (exact): \(exerciseName) -> \(filename)")
                #endif
                return url
            }
        }
        
        // FALLBACK: Check legacy hardcoded mapping
        if let filename = videoMapping[exerciseName] {
            let urlString = "\(storageBaseURL)/\(filename)"
            if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                #if DEBUG
                print("📹 Legacy mapping: \(exerciseName) -> \(filename)")
                #endif
                return url
            }
        }
        
        // Try fuzzy match on legacy hardcoded mapping
        for (key, filename) in videoMapping {
            if key.lowercased() == normalizedName {
                let urlString = "\(storageBaseURL)/\(filename)"
                if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                    #if DEBUG
                    print("📹 Legacy fuzzy mapping: \(exerciseName) -> \(filename)")
                    #endif
                    return url
                }
            }
        }
        
        #if DEBUG
        print("⚠️ No video mapping found for: \(exerciseName)")
        #endif
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
                #if DEBUG
                print("📹 Fallback to direct filename: \(exerciseName) -> \(filename)")
                #endif
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
            print("📥 Cached video: \(exerciseName)")
            return true
        } catch {
            print("❌ Failed to cache video: \(error)")
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
            print("🗑️ Video cache cleared")
        } catch {
            print("❌ Failed to clear cache: \(error)")
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
        playerLayer.videoGravity = .resizeAspect
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
    
    private var backgroundColor: Color {
        .white // Pure white to match exercise video content backgrounds
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Clean background
            backgroundColor
            
            if let player = playerManager.player, showPlayer {
                // 🎬 Video ready - show immediately with quick fade, aligned to top
                // Custom video view without native controls
                VideoPlayerLayerView(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.animation(.easeIn(duration: 0.1)))
            } else if playerManager.isLoading {
                // ⏳ Very brief loading (should be <500ms with new engine)
                VStack(spacing: 10) {
                    // Subtle pulsing animation
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(categoryColor.opacity(0.4))
                        .symbolEffect(.pulse)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 🚫 No video available
                VStack(spacing: 14) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 64))
                        .foregroundColor(categoryColor.opacity(0.4))
                    
                    Text("Video Coming Soon")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240) // Fixed height, content aligned to top
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            
            // 🚀 Load video using high-performance engine
            playerManager.loadVideo(for: exerciseName, videoFilename: videoFilename)
            
            // Quick reveal after player is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeIn(duration: 0.1)) {
                    showPlayer = true
                }
            }
        }
        .onDisappear {
            playerManager.pause()
        }
        .task {
            // Periodic check to ensure looping stays active while view is visible
            // Only check every 10 seconds to avoid spam
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Every 10 seconds
                // Only check if player exists and video should be playing
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
    @Published var error: Error?
    
    var queuePlayer: AVQueuePlayer?
    var playerLooper: AVPlayerLooper?  // ⚡️ CRITICAL: Must store looper reference or it gets deallocated
    
    func loadVideo(for exerciseName: String, videoFilename: String? = nil) {
        isLoading = true
        hasRetriedLooper = false  // Reset retry flag for new video
        
        // 👤 ALWAYS check GenderFilterService FIRST to respect user's gender preference
        // Only fall back to provided videoFilename if gender service has no match
        let genderAwareFilename = GenderFilterService.shared.getVideoFilename(for: exerciseName, fallbackToOpposite: true) ?? videoFilename
        
        // 🚀 Use high-performance VideoPlaybackEngine (instant if cached)
        // CRITICAL: Get both player AND looper to ensure looping works
        if let playerWithLooper = VideoPlaybackEngine.shared.getPlayerWithLooper(for: exerciseName, videoFilename: genderAwareFilename) {
            DispatchQueue.main.async { [weak self] in
                self?.queuePlayer = playerWithLooper.player
                self?.player = playerWithLooper.player
                self?.playerLooper = playerWithLooper.looper  // ⚡️ STORE LOOPER REFERENCE!
                self?.hasRetriedLooper = false  // Reset on successful load
                self?.isLoading = false
                
                #if DEBUG
                let cacheStatus = VideoPlaybackEngine.shared.isReadyForInstantPlay(exerciseName: exerciseName) ? "cached" : "new"
                let genderMatch = GenderFilterService.shared.hasPreferredGenderVideo(for: exerciseName) ? "preferred" : "fallback"
                print("🎬 Video ready (\(cacheStatus), \(genderMatch) gender, looper: ✅): \(exerciseName)")
                #endif
            }
            return
        }
        
        // Fallback: Try legacy VideoStreamingService
        if let preloadedPlayer = VideoStreamingService.shared.getPreloadedPlayer(for: exerciseName) {
            setupLegacyPlayer(from: preloadedPlayer, exerciseName: exerciseName)
            isLoading = false
            return
        }
        
        // Last resort: Create directly with gender-aware URL
        if let filename = genderAwareFilename, !filename.isEmpty {
            let storageBaseURL = "https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev"
            let urlString = "\(storageBaseURL)/\(filename)"
            if let videoURL = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                createDirectPlayer(url: videoURL, exerciseName: exerciseName)
                return
            }
        }
        
        // Get URL from VideoStreamingService with gender awareness
        if let videoURL = VideoStreamingService.shared.getGenderAwareVideoURL(for: exerciseName) {
            createDirectPlayer(url: videoURL, exerciseName: exerciseName)
            return
        }
        
        #if DEBUG
        print("⚠️ No video found for: \(exerciseName)")
        #endif
        isLoading = false
    }
    
    private func createDirectPlayer(url: URL, exerciseName: String) {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            "AVURLAssetOutOfBandMIMETypeKey": "video/mp4"
        ])
        
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        playerItem.preferredForwardBufferDuration = 2
        
        let qp = AVQueuePlayer(playerItem: playerItem)
        // ⚡️ CRITICAL: Store looper reference - without this, looper is deallocated and video won't loop!
        self.playerLooper = AVPlayerLooper(player: qp, templateItem: playerItem)
        
        qp.automaticallyWaitsToMinimizeStalling = false
        qp.play()
        
        self.queuePlayer = qp
        self.player = qp
        self.isLoading = false
    }
    
    private func setupLegacyPlayer(from sourcePlayer: AVPlayer, exerciseName: String) {
        guard let currentItem = sourcePlayer.currentItem else { return }
        
        let asset = currentItem.asset
        let loopItem = AVPlayerItem(asset: asset)
        loopItem.preferredForwardBufferDuration = 3
        
        let qp = AVQueuePlayer(playerItem: loopItem)
        // ⚡️ CRITICAL: Store looper reference - without this, looper is deallocated and video won't loop!
        self.playerLooper = AVPlayerLooper(player: qp, templateItem: loopItem)
        
        self.queuePlayer = qp
        self.player = qp
        qp.play()
    }
    
    func pause() {
        player?.pause()
    }
    
    func play() {
        // Ensure player plays and looper is still active
        if let looper = playerLooper, looper.status != .ready {
            print("⚠️ [VIDEO] Looper not ready, recreating...")
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
            print("🔄 [VIDEO] Creating looper for continuous playback")
            if let currentItem = qp.currentItem {
                self.playerLooper = AVPlayerLooper(player: qp, templateItem: currentItem)
                hasRetriedLooper = true
            }
        }
        
        // Always try to play if paused
        qp.play()
    }
    
    deinit {
        pause()
    }
}

