import SwiftUI
import UIKit

// MARK: - Profile Photo Cache (Persistent)
/// Caches the user's profile photo to disk for instant loading
final class ProfilePhotoCache {
    static let shared = ProfilePhotoCache()
    
    private let fileManager = FileManager.default
    private var memoryCache: UIImage?
    private let cacheFileName = "profile_photo.jpg"
    
    private var cacheURL: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(cacheFileName)
    }
    
    private init() {
        // ⚡️ Cold-start Phase 4: prefer pre-decoded UIImage from
        // StartupCachePreloader (read & decoded on bg before init runs on main).
        // Also pre-flattens via UIGraphicsBeginImageContext so the first
        // on-screen render avoids a UIKit decode-on-render hitch.
        if let pre = StartupCachePreloader.consumeProfilePhoto() {
            memoryCache = pre
            AppLogger.debug("📸 Profile photo loaded from pre-decoded cache (instant)", category: .general)
        } else {
            loadFromDisk()
        }
    }
    
    /// Get cached profile photo (memory first, then disk)
    var cachedImage: UIImage? {
        if let memory = memoryCache {
            return memory
        }
        loadFromDisk()
        return memoryCache
    }
    
    /// Cache the profile photo to memory and disk
    func cacheImage(_ image: UIImage) {
        memoryCache = image
        saveToDisk(image)
    }
    
    /// Clear the cached profile photo
    func clearCache() {
        memoryCache = nil
        if let url = cacheURL {
            try? fileManager.removeItem(at: url)
        }
        AppLogger.debug("🗑️ Profile photo cache cleared", category: .general)
    }
    
    /// ⚡️ MEMORY FIX: Clear only in-memory image (disk stays for fast reload).
    /// Called by MemoryPressureHandler during emergency cleanup.
    func clearMemoryOnly() {
        memoryCache = nil
        AppLogger.debug("💾 Profile photo memory cache cleared (disk retained)", category: .general)
    }
    
    private func loadFromDisk() {
        guard let url = cacheURL,
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return
        }
        memoryCache = image
        AppLogger.debug("📸 Profile photo loaded from disk cache", category: .general)
    }
    
    private func saveToDisk(_ image: UIImage) {
        guard let url = cacheURL,
              let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        try? data.write(to: url)
        AppLogger.debug("💾 Profile photo saved to disk cache", category: .general)
    }
}
