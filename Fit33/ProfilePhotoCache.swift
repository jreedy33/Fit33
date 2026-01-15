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
        // Load from disk into memory on init
        loadFromDisk()
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
        print("🗑️ Profile photo cache cleared")
    }
    
    private func loadFromDisk() {
        guard let url = cacheURL,
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return
        }
        memoryCache = image
        print("📸 Profile photo loaded from disk cache")
    }
    
    private func saveToDisk(_ image: UIImage) {
        guard let url = cacheURL,
              let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        try? data.write(to: url)
        print("💾 Profile photo saved to disk cache")
    }
}
