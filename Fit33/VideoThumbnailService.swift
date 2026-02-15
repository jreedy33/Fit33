import UIKit
import AVFoundation
import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - VIDEO THUMBNAIL SERVICE (YouTube-Style Instant Playback)
// ═══════════════════════════════════════════════════════════════════════════════
//
// 🎯 THE YOUTUBE TRICK: Users don't need the video to actually BE playing to
//    perceive instant playback. They just need to SEE something instantly.
//
// How it works:
//   1. First time a video plays → extract first frame → cache to disk forever
//   2. Every subsequent time → show cached poster frame INSTANTLY (0ms)
//   3. Real video loads behind the poster → crossfade when ready (~200-500ms)
//   4. User perceives: "wow, that loaded instantly"
//
// Memory comparison:
//   - 1 AVPlayer with buffer ≈ 20-50MB
//   - 1 poster frame JPEG   ≈ 20-50KB  (1000x cheaper!)
//   - We can cache 500 poster frames for the cost of 1 AVPlayer
//
// Bonus: CDN connection pre-warming
//   - Single HEAD request warms DNS + TLS to Cloudflare R2
//   - HTTP/2 multiplexing reuses that connection for ALL video requests
//   - Saves 100-300ms on first video load
//
// ═══════════════════════════════════════════════════════════════════════════════

final class VideoThumbnailService {
    static let shared = VideoThumbnailService()
    
    // MARK: - Poster Frame Cache
    
    /// In-memory cache: auto-evicts under memory pressure (NSCache magic)
    /// 200 thumbnails × ~30KB each ≈ 6MB — negligible compared to AVPlayers
    private let memoryCache = NSCache<NSString, UIImage>()
    
    /// Disk cache directory: thumbnails persist forever (they never change)
    private let diskCacheDir: URL?
    private let fileManager = FileManager.default
    
    // MARK: - CDN Connection Pre-warming
    
    private let r2BaseURL = "https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev"
    private var isConnectionWarmed = false
    private var warmingTask: URLSessionDataTask?
    
    /// Dedicated session for pre-warming (short timeouts, minimal resources)
    private let warmingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    // MARK: - Background Processing
    
    private let thumbnailQueue = DispatchQueue(label: "video.thumbnails", qos: .utility)
    private var generatingThumbnails: Set<String> = []
    private let generationLock = NSLock()
    
    // MARK: - Init
    
    private init() {
        // Configure memory cache
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 15 * 1024 * 1024 // 15MB max
        
        // Setup disk cache directory
        diskCacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("video_thumbnails")
        
        if let dir = diskCacheDir {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        // Pre-warm CDN connection on init (one tiny HEAD request)
        prewarmCDNConnection()
        
        #if DEBUG
        let diskCount = countDiskThumbnails()
        print("🖼️ [THUMBNAIL] Initialized — \(diskCount) poster frames on disk")
        #endif
    }
    
    // MARK: - 🚀 Public API: Get Poster Frame
    
    /// Get cached poster frame for an exercise (SYNCHRONOUS — instant return)
    /// Returns nil if not yet cached (first-time play will generate it)
    func getPosterFrame(for exerciseName: String) -> UIImage? {
        let key = cacheKey(for: exerciseName)
        
        // 1. Check memory cache (instant)
        if let memoryImage = memoryCache.object(forKey: key as NSString) {
            return memoryImage
        }
        
        // 2. Check disk cache (fast — ~1-5ms for a small JPEG)
        if let diskImage = loadFromDisk(key: key) {
            // Promote to memory cache for next access
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }
        
        return nil
    }
    
    /// Check if we have a poster frame cached for this exercise
    func hasPosterFrame(for exerciseName: String) -> Bool {
        let key = cacheKey(for: exerciseName)
        
        if memoryCache.object(forKey: key as NSString) != nil {
            return true
        }
        
        if let dir = diskCacheDir {
            return fileManager.fileExists(atPath: dir.appendingPathComponent("\(key).jpg").path)
        }
        
        return false
    }
    
    // MARK: - 🎬 Poster Frame Generation
    
    /// Capture poster frame from a PLAYING video (FREE — no extra network cost)
    /// Call this when a video successfully starts playing for the first time
    func capturePosterFrame(from player: AVPlayer, exerciseName: String) {
        let key = cacheKey(for: exerciseName)
        
        // Don't re-generate if we already have it
        guard !hasPosterFrame(for: exerciseName) else { return }
        
        // Don't generate concurrently for the same exercise
        generationLock.lock()
        guard !generatingThumbnails.contains(key) else {
            generationLock.unlock()
            return
        }
        generatingThumbnails.insert(key)
        generationLock.unlock()
        
        // Extract current frame from the player's video output
        guard let currentItem = player.currentItem else {
            markGenerationComplete(key)
            return
        }
        
        let asset = currentItem.asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270) // 16:9, good enough for poster
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        // Use the current playback time (which should be near the start)
        let time = player.currentTime()
        let captureTime = time.seconds > 0.1 ? time : CMTime(seconds: 0.1, preferredTimescale: 600)
        
        thumbnailQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let cgImage = try generator.copyCGImage(at: captureTime, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                
                // Cache to memory + disk
                self.memoryCache.setObject(thumbnail, forKey: key as NSString)
                self.saveToDisk(thumbnail, key: key)
                
                #if DEBUG
                print("🖼️ [THUMBNAIL] Captured poster frame: \(exerciseName)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ [THUMBNAIL] Failed to capture: \(exerciseName) — \(error.localizedDescription)")
                #endif
            }
            
            self.markGenerationComplete(key)
        }
    }
    
    /// Generate poster frame from a video URL (for pre-generating before first play)
    /// This downloads a small amount of video data (~100-500KB) to extract the first frame
    func generatePosterFrame(exerciseName: String, videoURL: URL) {
        let key = cacheKey(for: exerciseName)
        
        // Don't re-generate if we already have it
        guard !hasPosterFrame(for: exerciseName) else { return }
        
        // Don't generate concurrently
        generationLock.lock()
        guard !generatingThumbnails.contains(key) else {
            generationLock.unlock()
            return
        }
        generatingThumbnails.insert(key)
        generationLock.unlock()
        
        thumbnailQueue.async { [weak self] in
            guard let self = self else { return }
            
            let asset = AVURLAsset(url: videoURL, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: false
            ])
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270)
            // Wide tolerance = faster, uses first available keyframe
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 2.0, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                
                self.memoryCache.setObject(thumbnail, forKey: key as NSString)
                self.saveToDisk(thumbnail, key: key)
                
                #if DEBUG
                print("🖼️ [THUMBNAIL] Generated poster frame: \(exerciseName)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ [THUMBNAIL] Generation failed: \(exerciseName) — \(error.localizedDescription)")
                #endif
            }
            
            self.markGenerationComplete(key)
        }
    }
    
    // MARK: - 🌐 CDN Connection Pre-warming
    
    /// Pre-warm the Cloudflare R2 connection (DNS + TLS handshake)
    /// One HEAD request warms the connection for ALL subsequent video requests
    /// HTTP/2 multiplexing means a single connection serves all videos
    func prewarmCDNConnection() {
        guard !isConnectionWarmed else { return }
        
        // Send a tiny HEAD request to any valid path on the CDN
        // This establishes: DNS resolution → TCP connection → TLS handshake
        // Total cost: ~1KB network, ~100-200ms time, saves 100-300ms per video later
        guard let url = URL(string: r2BaseURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        
        warmingTask = warmingSession.dataTask(with: request) { [weak self] _, response, _ in
            self?.isConnectionWarmed = true
            if let httpResponse = response as? HTTPURLResponse {
                #if DEBUG
                print("🌐 [THUMBNAIL] CDN connection pre-warmed (status: \(httpResponse.statusCode))")
                #endif
            }
        }
        warmingTask?.resume()
    }
    
    /// Pre-warm connection for specific video URLs (call for visible exercises)
    /// This resolves the specific video URL path while reusing the existing connection
    func prewarmVideoURLs(_ urls: [URL]) {
        // Only warm first 3 to avoid unnecessary network
        for url in urls.prefix(3) {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 2
            
            warmingSession.dataTask(with: request) { _, _, _ in
                // Don't care about response — just warming the connection path
            }.resume()
        }
    }
    
    // MARK: - 🧹 Cache Management
    
    /// Clear memory cache only (for memory pressure — disk cache stays)
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        #if DEBUG
        print("💾 [THUMBNAIL] Memory cache cleared (disk cache retained)")
        #endif
    }
    
    /// Clear everything (disk + memory)
    func clearAllCaches() {
        memoryCache.removeAllObjects()
        if let dir = diskCacheDir {
            try? fileManager.removeItem(at: dir)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        #if DEBUG
        print("🗑️ [THUMBNAIL] All caches cleared")
        #endif
    }
    
    // MARK: - Private: Disk Operations
    
    private func cacheKey(for exerciseName: String) -> String {
        // Include gender preference in key so thumbnails update when gender changes
        let gender = GenderFilterService.shared.preferredGender.rawValue.lowercased()
        let base = exerciseName.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "\(base)_\(gender)"
    }
    
    private func loadFromDisk(key: String) -> UIImage? {
        guard let dir = diskCacheDir else { return nil }
        let filePath = dir.appendingPathComponent("\(key).jpg")
        
        guard fileManager.fileExists(atPath: filePath.path),
              let data = try? Data(contentsOf: filePath),
              let image = UIImage(data: data) else {
            return nil
        }
        
        return image
    }
    
    private func saveToDisk(_ image: UIImage, key: String) {
        guard let dir = diskCacheDir,
              let data = image.jpegData(compressionQuality: 0.6) else { return } // 60% quality = small + good enough
        
        let filePath = dir.appendingPathComponent("\(key).jpg")
        try? data.write(to: filePath, options: .atomic)
    }
    
    private func markGenerationComplete(_ key: String) {
        generationLock.lock()
        generatingThumbnails.remove(key)
        generationLock.unlock()
    }
    
    private func countDiskThumbnails() -> Int {
        guard let dir = diskCacheDir else { return 0 }
        return (try? fileManager.contentsOfDirectory(atPath: dir.path).count) ?? 0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - POSTER FRAME VIEW (Reusable SwiftUI Component)
// ═══════════════════════════════════════════════════════════════════════════════

/// Shows a cached poster frame with a subtle play overlay
/// Used as the "instant" layer before the real video loads
struct VideoPosterFrameView: View {
    let exerciseName: String
    let categoryColor: Color
    
    @State private var posterImage: UIImage?
    
    var body: some View {
        ZStack {
            if let image = posterImage {
                // Poster frame available — show it
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else {
                // No poster frame yet — show a clean gradient placeholder
                // (Much better than a loading spinner — feels intentional)
                LinearGradient(
                    colors: [
                        categoryColor.opacity(0.08),
                        categoryColor.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .aspectRatio(16/9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [categoryColor.opacity(0.5), categoryColor.opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
        }
        .onAppear {
            posterImage = VideoThumbnailService.shared.getPosterFrame(for: exerciseName)
        }
    }
}
