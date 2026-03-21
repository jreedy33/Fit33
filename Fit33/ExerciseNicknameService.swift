import Foundation
import SwiftUI

// MARK: - Exercise Nickname Service
/// Manages user-specific exercise nicknames
/// Allows users to rename exercises with custom names that display throughout the app
/// while keeping data mapped to official exercise names

class ExerciseNicknameService: ObservableObject {
    static let shared = ExerciseNicknameService()
    
    // Cache of nicknames: official_name -> nickname
    @Published private(set) var nicknames: [String: String] = [:]
    
    // Reverse lookup: nickname -> official_name
    private var reverseNicknames: [String: String] = [:]
    
    // Loading state
    @Published var isLoaded = false
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get the display name for an exercise (nickname if exists, otherwise official name)
    func displayName(for officialName: String) -> String {
        return nicknames[officialName.lowercased()] ?? officialName
    }
    
    /// Get the display name for an Exercise object
    func displayName(for exercise: Exercise) -> String {
        guard let name = exercise.name else {
            // If exercises are still loading, show loading state
            return ExerciseLibraryService.shared.isExercisesReady ? "Exercise" : "Loading..."
        }
        return displayName(for: name)
    }
    
    /// Check if an exercise has a nickname
    func hasNickname(for officialName: String) -> Bool {
        return nicknames[officialName.lowercased()] != nil
    }
    
    /// Get the official name from a nickname (for reverse lookup)
    func officialName(for nickname: String) -> String? {
        return reverseNicknames[nickname.lowercased()]
    }
    
    /// Auto-capitalize a nickname (Title Case)
    func autoCapitalize(_ text: String) -> String {
        let result = text.split(separator: " ")
            .map { word in
                let lowercased = word.lowercased()
                if ["a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with"].contains(lowercased) {
                    return String(lowercased)
                }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
        return result.prefix(1).uppercased() + result.dropFirst()
    }
    
    // MARK: - Data Management
    
    /// Load all nicknames for the current user from Supabase
    func loadNicknames() async {
        do {
            let fetchedNicknames = try await SupabaseManager.shared.fetchExerciseNicknames()
            
            await MainActor.run {
                self.nicknames.removeAll()
                self.reverseNicknames.removeAll()
                
                for nickname in fetchedNicknames {
                    let key = nickname.officialName.lowercased()
                    self.nicknames[key] = nickname.nickname
                    self.reverseNicknames[nickname.nickname.lowercased()] = nickname.officialName
                }
                
                self.isLoaded = true
                #if DEBUG
                AppLogger.info("✅ [NICKNAMES] Loaded \(self.nicknames.count) exercise nicknames", category: .workout)
                #endif
            }
        } catch {
            #if DEBUG
            AppLogger.warning("⚠️ [NICKNAMES] Failed to load: \(error)", category: .workout)
            #endif
            await MainActor.run {
                self.isLoaded = true // Mark as loaded even on error so app doesn't wait
            }
        }
    }
    
    /// Save or update a nickname for an exercise
    func setNickname(_ nickname: String, for officialName: String, exerciseId: UUID? = nil) async throws {
        let capitalizedNickname = autoCapitalize(nickname.trimmingCharacters(in: .whitespacesAndNewlines))
        
        guard !capitalizedNickname.isEmpty else {
            throw NicknameError.emptyNickname
        }
        
        // Save to Supabase
        try await SupabaseManager.shared.saveExerciseNickname(
            officialName: officialName,
            nickname: capitalizedNickname,
            exerciseId: exerciseId
        )
        
        // Update local cache
        await MainActor.run {
            let key = officialName.lowercased()
            
            // Remove old reverse mapping if exists
            if let oldNickname = self.nicknames[key] {
                self.reverseNicknames.removeValue(forKey: oldNickname.lowercased())
            }
            
            // Set new mappings
            self.nicknames[key] = capitalizedNickname
            self.reverseNicknames[capitalizedNickname.lowercased()] = officialName
        }
        
        #if DEBUG
        AppLogger.info("✅ [NICKNAMES] Set '\(officialName)' -> '\(capitalizedNickname)'", category: .workout)
        #endif
    }
    
    /// Remove a nickname for an exercise (revert to official name)
    func removeNickname(for officialName: String) async throws {
        try await SupabaseManager.shared.deleteExerciseNickname(officialName: officialName)
        
        await MainActor.run {
            let key = officialName.lowercased()
            if let oldNickname = self.nicknames[key] {
                self.reverseNicknames.removeValue(forKey: oldNickname.lowercased())
            }
            self.nicknames.removeValue(forKey: key)
        }
        
        #if DEBUG
        AppLogger.info("✅ [NICKNAMES] Removed nickname for '\(officialName)'", category: .workout)
        #endif
    }
    
    /// Clear all cached nicknames (e.g., on logout)
    func clearCache() {
        nicknames.removeAll()
        reverseNicknames.removeAll()
        isLoaded = false
    }
    
    // MARK: - Search Support
    
    /// Search for exercises including nickname matches
    /// Returns array of official names that match the search term (either by official name or nickname)
    func searchExercises(query: String, in officialNames: [String]) -> [String] {
        let lowercasedQuery = query.lowercased()
        
        return officialNames.filter { officialName in
            // Match by official name
            if officialName.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            // Match by nickname
            if let nickname = nicknames[officialName.lowercased()],
               nickname.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            return false
        }
    }
}

// MARK: - Errors
enum NicknameError: Error, LocalizedError {
    case emptyNickname
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .emptyNickname:
            return "Nickname cannot be empty"
        case .saveFailed:
            return "Failed to save nickname"
        }
    }
}

// MARK: - DTO for Supabase
struct ExerciseNicknameDTO: Codable {
    let id: String
    let officialName: String
    let nickname: String
    let exerciseId: String?
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case officialName = "official_name"
        case nickname
        case exerciseId = "exercise_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - View Extension for Easy Access
extension View {
    /// Get the display name for an exercise (nickname or official name)
    func exerciseDisplayName(_ officialName: String) -> String {
        ExerciseNicknameService.shared.displayName(for: officialName)
    }
}

// MARK: - Exercise Extension
extension Exercise {
    /// Get the display name for this exercise (nickname if user has set one, otherwise official name)
    var displayName: String {
        ExerciseNicknameService.shared.displayName(for: self)
    }
}
