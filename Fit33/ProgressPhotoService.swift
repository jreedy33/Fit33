import SwiftUI
import UIKit

// MARK: - Models

enum PhotoType: String, CaseIterable, Codable {
    case front, side, back
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var icon: String {
        switch self {
        case .front: return "person.fill"
        case .side: return "person.fill.turn.right"
        case .back: return "person.fill.turn.down"
        }
    }
}

struct ProgressPhoto: Identifiable, Codable {
    let id: UUID
    let userId: String
    let photoType: String
    let localFilename: String
    var cloudUrl: String?
    var weightAtCapture: Double?
    var bodyFatAtCapture: Double?
    var programName: String?
    var programWeek: Int?
    var notes: String?
    let takenAt: Date
    let createdAt: Date
    
    var type: PhotoType {
        PhotoType(rawValue: photoType) ?? .front
    }
    
    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", photoType = "photo_type"
        case localFilename = "local_filename", cloudUrl = "cloud_url"
        case weightAtCapture = "weight_at_capture", bodyFatAtCapture = "body_fat_at_capture"
        case programName = "program_name", programWeek = "program_week"
        case notes, takenAt = "taken_at", createdAt = "created_at"
    }
}

struct ProgressPhotoGroup: Identifiable {
    let id = UUID()
    let date: Date
    let photos: [ProgressPhoto]
    var weight: Double? { photos.first?.weightAtCapture }
    var bodyFat: Double? { photos.first?.bodyFatAtCapture }
}

// MARK: - Service

class ProgressPhotoService: ObservableObject {
    static let shared = ProgressPhotoService()
    
    @Published var photos: [ProgressPhoto] = []
    @Published var isLoading = false
    
    private let fileManager = FileManager.default
    
    private var photosDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("progress_photos", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private init() {
        loadLocalMetadata()
    }
    
    // MARK: - Photo Storage
    
    func savePhoto(image: UIImage, type: PhotoType, notes: String? = nil) -> ProgressPhoto? {
        let filename = "\(type.rawValue)_\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        
        do {
            try data.write(to: fileURL)
        } catch {
            print("Failed to save progress photo: \(error)")
            return nil
        }
        
        let photo = ProgressPhoto(
            id: UUID(),
            userId: "",
            photoType: type.rawValue,
            localFilename: filename,
            cloudUrl: nil,
            weightAtCapture: currentWeight(),
            bodyFatAtCapture: currentBodyFat(),
            programName: currentProgramName(),
            programWeek: nil,
            notes: notes,
            takenAt: Date(),
            createdAt: Date()
        )
        
        photos.append(photo)
        photos.sort { $0.takenAt > $1.takenAt }
        saveLocalMetadata()
        
        return photo
    }
    
    func loadImage(for photo: ProgressPhoto) -> UIImage? {
        let fileURL = photosDirectory.appendingPathComponent(photo.localFilename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
    
    func deletePhoto(_ photo: ProgressPhoto) {
        let fileURL = photosDirectory.appendingPathComponent(photo.localFilename)
        try? fileManager.removeItem(at: fileURL)
        photos.removeAll { $0.id == photo.id }
        saveLocalMetadata()
    }
    
    func latestPhoto(ofType type: PhotoType) -> ProgressPhoto? {
        photos.first { $0.photoType == type.rawValue }
    }
    
    var daysSinceLastPhoto: Int? {
        guard let latest = photos.first else { return nil }
        return Calendar.current.dateComponents([.day], from: latest.takenAt, to: Date()).day
    }
    
    var groupedByDate: [ProgressPhotoGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: photos) { photo in
            calendar.startOfDay(for: photo.takenAt)
        }
        return grouped.map { ProgressPhotoGroup(date: $0.key, photos: $0.value) }
            .sorted { $0.date > $1.date }
    }
    
    // MARK: - Metadata Persistence (local JSON)
    
    private var metadataURL: URL {
        photosDirectory.appendingPathComponent("metadata.json")
    }
    
    private func saveLocalMetadata() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(photos) else { return }
        try? data.write(to: metadataURL)
    }
    
    private func loadLocalMetadata() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        photos = (try? decoder.decode([ProgressPhoto].self, from: data)) ?? []
        photos.sort { $0.takenAt > $1.takenAt }
    }
    
    // MARK: - Context Helpers
    
    private func currentWeight() -> Double? {
        nil // Will pull from WeightTrackingService or UserManager when integrated
    }
    
    private func currentBodyFat() -> Double? {
        nil // Will pull from InBodyService when integrated
    }
    
    private func currentProgramName() -> String? {
        nil // Will pull from active program when integrated
    }
}
