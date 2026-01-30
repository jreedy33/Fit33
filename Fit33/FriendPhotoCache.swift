import SwiftUI
import UIKit

// MARK: - Friend Photo Cache
/// Caches friends' profile photos in memory and disk for fast loading throughout the app
/// Used in: FriendProfileView, ReceivedWorkoutsView, FriendsListView, ReceivedWorkoutPreviewWidget

final class FriendPhotoCache {
    static let shared = FriendPhotoCache()
    
    private let fileManager = FileManager.default
    private var memoryCache: NSCache<NSString, UIImage> = NSCache()
    private let cacheDirectoryName = "friend_photos"
    
    private var cacheDirectoryURL: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(cacheDirectoryName)
    }
    
    private init() {
        // Configure memory cache
        memoryCache.countLimit = 50 // Max 50 friend photos in memory
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        
        // Create cache directory if needed
        if let cacheDir = cacheDirectoryURL {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        print("📸 [FRIEND CACHE] Initialized")
    }
    
    // MARK: - Public API
    
    /// Get cached image for a friend (memory first, then disk)
    func getImage(for friendId: String) -> UIImage? {
        // Check memory cache first
        if let memoryImage = memoryCache.object(forKey: friendId as NSString) {
            return memoryImage
        }
        
        // Check disk cache
        if let diskImage = loadFromDisk(friendId: friendId) {
            // Restore to memory cache
            memoryCache.setObject(diskImage, forKey: friendId as NSString)
            return diskImage
        }
        
        return nil
    }
    
    /// Cache an image for a friend
    func cacheImage(_ image: UIImage, for friendId: String) {
        // Save to memory
        memoryCache.setObject(image, forKey: friendId as NSString)
        
        // Save to disk asynchronously
        Task.detached(priority: .background) {
            await self.saveToDisk(image, friendId: friendId)
        }
    }
    
    /// Download and cache a friend's photo from URL
    @MainActor
    func downloadAndCache(url: URL, friendId: String) async -> UIImage? {
        // Check cache first
        if let cached = getImage(for: friendId) {
            return cached
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                cacheImage(image, for: friendId)
                return image
            }
        } catch {
            print("⚠️ [FRIEND CACHE] Failed to download photo for \(friendId): \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Preload photos for multiple friends
    func preloadPhotos(for friends: [(id: String, url: String?)]) {
        Task {
            for friend in friends {
                guard let urlString = friend.url,
                      let url = URL(string: urlString),
                      getImage(for: friend.id) == nil else { continue }
                
                _ = await downloadAndCache(url: url, friendId: friend.id)
            }
        }
    }
    
    /// Clear all cached photos
    func clearCache() {
        memoryCache.removeAllObjects()
        if let cacheDir = cacheDirectoryURL {
            try? fileManager.removeItem(at: cacheDir)
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        print("🗑️ [FRIEND CACHE] Cache cleared")
    }
    
    /// Remove cached photo for a specific friend
    func removeImage(for friendId: String) {
        memoryCache.removeObject(forKey: friendId as NSString)
        if let cacheDir = cacheDirectoryURL {
            let filePath = cacheDir.appendingPathComponent("\(friendId).jpg")
            try? fileManager.removeItem(at: filePath)
        }
    }
    
    // MARK: - Private Disk Operations
    
    private func loadFromDisk(friendId: String) -> UIImage? {
        guard let cacheDir = cacheDirectoryURL else { return nil }
        let filePath = cacheDir.appendingPathComponent("\(friendId).jpg")
        
        guard fileManager.fileExists(atPath: filePath.path),
              let data = try? Data(contentsOf: filePath),
              let image = UIImage(data: data) else {
            return nil
        }
        
        return image
    }
    
    private func saveToDisk(_ image: UIImage, friendId: String) async {
        guard let cacheDir = cacheDirectoryURL,
              let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        let filePath = cacheDir.appendingPathComponent("\(friendId).jpg")
        try? data.write(to: filePath)
    }
}

// MARK: - Cached Friend Photo View
/// Reusable SwiftUI view that shows a friend's photo with caching and fallback to initials

struct CachedFriendPhoto: View {
    let friendId: String
    let photoUrl: String?
    let name: String
    let size: CGFloat
    let showGradientRing: Bool
    let gradientColors: [Color]
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(
        friendId: String,
        photoUrl: String?,
        name: String,
        size: CGFloat = 50,
        showGradientRing: Bool = false,
        gradientColors: [Color] = [.blue, .purple]
    ) {
        self.friendId = friendId
        self.photoUrl = photoUrl
        self.name = name
        self.size = size
        self.showGradientRing = showGradientRing
        self.gradientColors = gradientColors
    }
    
    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return "??"
    }
    
    var body: some View {
        ZStack {
            // Optional gradient ring
            if showGradientRing {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size > 60 ? 3 : 2.5
                    )
                    .frame(width: size + 8, height: size + 8)
            }
            
            // Photo or initials
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Initials fallback with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                    
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: photoUrl) { _, _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard !isLoading else { return }
        
        // Check cache first
        if let cached = FriendPhotoCache.shared.getImage(for: friendId) {
            self.image = cached
            return
        }
        
        // Download if URL exists
        guard let urlString = photoUrl, let url = URL(string: urlString) else { return }
        
        isLoading = true
        Task {
            if let downloaded = await FriendPhotoCache.shared.downloadAndCache(url: url, friendId: friendId) {
                await MainActor.run {
                    self.image = downloaded
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Large Cached Friend Photo (For Profile Views)
/// Larger version with outer glow effect for profile headers

struct LargeCachedFriendPhoto: View {
    let friendId: String
    let photoUrl: String?
    let name: String
    let size: CGFloat
    let gradientColors: [Color]
    
    @State private var image: UIImage?
    
    init(
        friendId: String,
        photoUrl: String?,
        name: String,
        size: CGFloat = 100,
        gradientColors: [Color] = [.blue, .purple.opacity(0.8)]
    ) {
        self.friendId = friendId
        self.photoUrl = photoUrl
        self.name = name
        self.size = size
        self.gradientColors = gradientColors
    }
    
    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return "??"
    }
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradientColors.map { $0.opacity(0.3) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size + 10, height: size + 10)
                .blur(radius: 20)
            
            // Photo or gradient with initials
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                    
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        // Check cache first
        if let cached = FriendPhotoCache.shared.getImage(for: friendId) {
            self.image = cached
            return
        }
        
        // Download if URL exists
        guard let urlString = photoUrl, let url = URL(string: urlString) else { return }
        
        Task {
            if let downloaded = await FriendPhotoCache.shared.downloadAndCache(url: url, friendId: friendId) {
                await MainActor.run {
                    self.image = downloaded
                }
            }
        }
    }
}
