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
    
    /// Get the display name for an exercise (nickname if exists, otherwise the
    /// smart-suffix presentation form of the official name).
    func displayName(for officialName: String) -> String {
        if let nickname = nicknames[officialName.lowercased()] {
            return nickname
        }
        return presentationName(for: officialName)
    }
    
    /// Get the display name for an Exercise object
    func displayName(for exercise: Exercise) -> String {
        // Defensive: return an empty string for a nil-name row so callers can filter it out.
        // Rendering "Exercise" / "Loading..." on a grey card is the exact placeholder state
        // we never want to show — the Exercise Library view now filters these rows before
        // they reach the card renderer (see ExerciseLibraryView.body).
        guard let name = exercise.name, !name.isEmpty else { return "" }
        return displayName(for: name)
    }

    /// Presentation-layer rewrite of the canonical exercise name. Currently
    /// only swaps the whole word "And" for "&" ("Clean And Press" → "Clean &
    /// Press"); the trailing-parenthetical equipment suffix is preserved
    /// everywhere so "(Dumbbell)" / "(EZ Bar)" / etc. remain visible.
    ///
    /// Smart-suffix stripping based on `ExerciseLibraryService.isBaseNameAmbiguous`
    /// is intentionally disabled while the product direction is being reviewed.
    /// The index is still maintained by `ExerciseLibraryService` so it can be
    /// re-enabled by restoring the stem-substitution branch.
    func presentationName(for officialName: String) -> String {
        let trimmed = officialName.trimmingCharacters(in: .whitespaces)
        return Self.replaceAndWithAmpersand(in: trimmed)
    }

    /// Whole-word "And" → "&" rewrite used by the display layer. Case-sensitive
    /// on purpose (Title Case "And" only) so we never chop "and" inside words
    /// like "Handstand" or "Random". Precompiled once at load time.
    private static let andWordRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\bAnd\\b", options: [])
    }()

    static func replaceAndWithAmpersand(in text: String) -> String {
        guard let regex = andWordRegex, !text.isEmpty else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "&")
    }

    /// Split a presentation name into a main line + optional variant line.
    ///
    /// Names shaped like `"<base> - <descriptor> (<equipment>)"` — e.g.
    /// `"Bench Press - Close Grip (Barbell)"` — become:
    ///   main:    `"Bench Press (Barbell)"`
    ///   variant: `"Close Grip"`
    ///
    /// The equipment suffix travels with the base so the main line stays
    /// "what movement / what tool" and the variant line is the qualifier the
    /// UI can render smaller. Names without `" - "` in the stem return
    /// `(name, nil)` — the card falls back to the single-line layout.
    ///
    /// Splits on the FIRST `" - "`, so chained descriptors (e.g. `"Curl -
    /// Alternating - Single Arm"`) collapse into one variant line.
    static func splitPresentation(_ name: String) -> (main: String, variant: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (trimmed, nil) }

        // Peel a trailing " (...)" segment off the end, if present.
        var stem = trimmed
        var suffix = ""
        if trimmed.hasSuffix(")"),
           let openRange = trimmed.range(of: " (", options: .backwards) {
            suffix = String(trimmed[openRange.lowerBound...])
            stem = String(trimmed[..<openRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        // Require space-bounded " - " so hyphenated words ("Push-Up", "Side-Raise")
        // are not split.
        guard let dashRange = stem.range(of: " - ") else {
            return (trimmed, nil)
        }

        let base = String(stem[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let variant = String(stem[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, !variant.isEmpty else { return (trimmed, nil) }

        return (base + suffix, variant)
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
