import Foundation
import Combine

// MARK: - Gender Filter Service
/// Centralized service for managing gender-based content filtering
/// Apple Senior Engineer approach: Single source of truth for gender preference

final class GenderFilterService: ObservableObject {
    static let shared = GenderFilterService()
    
    // MARK: - Types
    
    enum Gender: String, CaseIterable {
        case male = "Male"
        case female = "Female"
        
        var opposite: Gender {
            self == .male ? .female : .male
        }
        
        var displayName: String { rawValue }
    }
    
    // MARK: - State
    
    /// User's preferred gender (observed from UserManager/UserDefaults)
    @Published private(set) var preferredGender: Gender = .male
    
    // Cache of exercises by gender availability
    private var exerciseGenderCache: [String: ExerciseGenderInfo] = [:]
    private var cacheLoaded = false
    private let cacheQueue = DispatchQueue(label: "gender.cache", qos: .userInitiated)
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Types
    
    struct ExerciseGenderInfo {
        let exerciseName: String
        var hasMaleVersion: Bool
        var hasFemaleVersion: Bool
        var maleVideoFilename: String?
        var femaleVideoFilename: String?
        
        var hasBothGenders: Bool {
            hasMaleVersion && hasFemaleVersion
        }
        
        func isAvailable(for gender: Gender) -> Bool {
            switch gender {
            case .male: return hasMaleVersion
            case .female: return hasFemaleVersion
            }
        }
        
        func videoFilename(for gender: Gender, withFallback: Bool = true) -> String? {
            switch gender {
            case .male:
                if let male = maleVideoFilename { return male }
                return withFallback ? femaleVideoFilename : nil
            case .female:
                if let female = femaleVideoFilename { return female }
                return withFallback ? maleVideoFilename : nil
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        loadGenderPreference()
        observeUserChanges()
        loadExerciseGenderCache()
        
        #if DEBUG
        AppLogger.debug("👤 GenderFilterService initialized - preference: \(preferredGender.rawValue)", category: .workout)
        #endif
    }
    
    // MARK: - Public API
    
    /// Get user's preferred gender
    func getPreferredGender() -> Gender {
        return preferredGender
    }
    
    /// Set user's preferred gender (call from settings/onboarding)
    func setPreferredGender(_ gender: Gender) {
        preferredGender = gender
        UserDefaults.standard.set(gender.rawValue, forKey: "preferredVideoGender")
        UserDefaults.standard.set(gender.rawValue, forKey: "userGender")
        
        // Sync to VideoStreamingService
        let videoGender: VideoStreamingService.VideoGender = gender == .female ? .female : .male
        VideoStreamingService.shared.setPreferredGender(videoGender)
        
        // 🔄 Clear video caches to ensure we load videos for the new gender
        VideoPlaybackEngine.shared.clearAllCaches()
        
        #if DEBUG
        AppLogger.debug("👤 Gender preference updated to: \(gender.rawValue) - video caches cleared", category: .workout)
        #endif
        
        // Notify all listeners
        NotificationCenter.default.post(name: .genderPreferenceChanged, object: gender)
    }
    
    /// Check if an exercise should be shown for the current user
    /// Returns true if:
    /// - Exercise has content for preferred gender, OR
    /// - Exercise only exists for opposite gender (fallback)
    func shouldShowExercise(_ exerciseName: String) -> Bool {
        let key = exerciseName.lowercased()
        
        guard let info = exerciseGenderCache[key] else {
            return true
        }
        
        if info.isAvailable(for: preferredGender) {
            return true
        }
        
        // Only show opposite-gender exercise if it's the ONLY version available
        if info.isAvailable(for: preferredGender.opposite) && !info.hasBothGenders {
            return true
        }
        
        return false
    }
    
    /// Get the correct video filename for an exercise based on gender
    func getVideoFilename(for exerciseName: String, fallbackToOpposite: Bool = true) -> String? {
        let key = exerciseName.lowercased()
        
        // 1. Try exact match first
        if let info = exerciseGenderCache[key] {
            let filename = info.videoFilename(for: preferredGender, withFallback: fallbackToOpposite)
            #if DEBUG
            AppLogger.debug("👤 [Gender] Exact match: '\(exerciseName)' -> \(preferredGender.rawValue) -> \(filename ?? "nil")", category: .workout)
            #endif
            return filename
        }
        
        // 2. Try normalized key (handles variations like "(Leaning)" vs "Lean")
        let normalizedKey = normalizeExerciseName(key)
        if let info = exerciseGenderCache[normalizedKey] {
            let filename = info.videoFilename(for: preferredGender, withFallback: fallbackToOpposite)
            #if DEBUG
            AppLogger.debug("👤 [Gender] Normalized match: '\(exerciseName)' -> '\(normalizedKey)' -> \(preferredGender.rawValue) -> \(filename ?? "nil")", category: .workout)
            #endif
            return filename
        }
        
        // 3. Try fuzzy match on cache keys
        for (cacheKey, info) in exerciseGenderCache {
            if normalizeExerciseName(cacheKey) == normalizedKey {
                let filename = info.videoFilename(for: preferredGender, withFallback: fallbackToOpposite)
                #if DEBUG
                AppLogger.debug("👤 [Gender] Fuzzy match: '\(exerciseName)' via '\(cacheKey)' -> \(preferredGender.rawValue) -> \(filename ?? "nil")", category: .workout)
                #endif
                return filename
            }
        }
        
        #if DEBUG
        AppLogger.debug("👤 [Gender] NO MATCH: '\(exerciseName)' (normalized: '\(normalizedKey)')", category: .workout)
        #endif
        return nil
    }
    
    /// Normalize exercise name for fuzzy matching
    /// Handles variations between database names and video filenames
    private func normalizeExerciseName(_ name: String) -> String {
        var normalized = name.lowercased()
        
        // 1. Handle common word substitutions
        normalized = normalized.replacingOccurrences(of: " leaning ", with: " lean ")
        normalized = normalized.replacingOccurrences(of: "(leaning)", with: "lean")
        
        // 2. Remove gender markers
        normalized = normalized.replacingOccurrences(of: "(male)", with: "")
        normalized = normalized.replacingOccurrences(of: "(female)", with: "")
        normalized = normalized.replacingOccurrences(of: " male ", with: " ")
        normalized = normalized.replacingOccurrences(of: " female ", with: " ")
        
        // 3. Remove difficulty level parentheses (but keep the word)
        normalized = normalized.replacingOccurrences(of: "(beginner)", with: "beginner")
        normalized = normalized.replacingOccurrences(of: "(beginner level)", with: "beginner level")
        normalized = normalized.replacingOccurrences(of: "(advanced)", with: "advanced")
        normalized = normalized.replacingOccurrences(of: "(intermediate)", with: "intermediate")
        
        // 4. Remove camera angle markers
        normalized = normalized.replacingOccurrences(of: "(front pov)", with: "")
        normalized = normalized.replacingOccurrences(of: "(side pov)", with: "")
        normalized = normalized.replacingOccurrences(of: "(back pov)", with: "")
        
        // 5. Remove version numbers
        if let versionRegex = try? NSRegularExpression(pattern: "\\s*\\(version \\d+\\)\\s*", options: []) {
            normalized = versionRegex.stringByReplacingMatches(in: normalized, options: [], range: NSRange(normalized.startIndex..., in: normalized), withTemplate: " ")
        }
        
        // 6. Normalize equipment modifiers (keep them but remove parentheses)
        normalized = normalized.replacingOccurrences(of: "(plate loaded)", with: "plate loaded")
        normalized = normalized.replacingOccurrences(of: "(on bench)", with: "on bench")
        normalized = normalized.replacingOccurrences(of: "(on a bench)", with: "on bench")
        normalized = normalized.replacingOccurrences(of: "(on stability ball)", with: "on stability ball")
        normalized = normalized.replacingOccurrences(of: "(on bosu ball)", with: "on bosu ball")
        normalized = normalized.replacingOccurrences(of: "(with rope)", with: "with rope")
        normalized = normalized.replacingOccurrences(of: "(rope attachment)", with: "rope attachment")
        normalized = normalized.replacingOccurrences(of: "(v bar)", with: "v bar")
        normalized = normalized.replacingOccurrences(of: "(sz bar)", with: "sz bar")
        
        // 7. Normalize position modifiers
        normalized = normalized.replacingOccurrences(of: "(bent knee)", with: "bent knee")
        normalized = normalized.replacingOccurrences(of: "(straight arm)", with: "straight arm")
        normalized = normalized.replacingOccurrences(of: "(bent arm)", with: "bent arm")
        normalized = normalized.replacingOccurrences(of: "(kneeling)", with: "kneeling")
        normalized = normalized.replacingOccurrences(of: "(on knees)", with: "on knees")
        
        // 8. Remove other common markers
        normalized = normalized.replacingOccurrences(of: "(wrong right)", with: "")
        normalized = normalized.replacingOccurrences(of: "(combo)", with: "combo")
        
        // 9. Remove any remaining parentheses content
        if let regex = try? NSRegularExpression(pattern: "\\s*\\([^)]*\\)\\s*", options: []) {
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: NSRange(normalized.startIndex..., in: normalized), withTemplate: " ")
        }
        
        // 10. Normalize whitespace - remove extra spaces
        normalized = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        
        // 11. Remove trailing suffixes (common in filenames)
        // Remove things like " fix", " fix2", etc at the end
        if let suffixRegex = try? NSRegularExpression(pattern: "\\s+fix\\d*$", options: []) {
            normalized = suffixRegex.stringByReplacingMatches(in: normalized, options: [], range: NSRange(normalized.startIndex..., in: normalized), withTemplate: "")
        }
        
        return normalized.trimmingCharacters(in: .whitespaces)
    }
    
    /// Check if exercise has video for preferred gender (vs fallback)
    func hasPreferredGenderVideo(for exerciseName: String) -> Bool {
        let key = exerciseName.lowercased()
        
        // Try exact match
        if let info = exerciseGenderCache[key] {
            return info.isAvailable(for: preferredGender)
        }
        
        // Try normalized match
        let normalizedKey = normalizeExerciseName(key)
        if let info = exerciseGenderCache[normalizedKey] {
            return info.isAvailable(for: preferredGender)
        }
        
        // Try fuzzy match
        for (cacheKey, info) in exerciseGenderCache {
            if normalizeExerciseName(cacheKey) == normalizedKey {
                return info.isAvailable(for: preferredGender)
            }
        }
        
        return false
    }
    
    /// Filter a list of exercises to show only appropriate ones for the user's gender
    func filterExercises(_ exercises: [Exercise]) -> [Exercise] {
        return exercises.filter { shouldShowExercise($0.name ?? "") }
    }
    
    /// Filter generated exercises by gender availability
    func filterGeneratedExercises(_ exercises: [GeneratedExercise]) -> [GeneratedExercise] {
        return exercises.filter { shouldShowExercise($0.name) }
    }
    
    // MARK: - Cache Management
    
    /// Refresh the exercise gender cache from VideoStreamingService
    func refreshCache() {
        loadExerciseGenderCache()
    }
    
    /// Get gender info for an exercise
    func getGenderInfo(for exerciseName: String) -> ExerciseGenderInfo? {
        return exerciseGenderCache[exerciseName.lowercased()]
    }
    
    // MARK: - Private Methods
    
    private func loadGenderPreference() {
        // Priority: 1. Explicit preference, 2. User profile gender, 3. Default male
        
        if let saved = UserDefaults.standard.string(forKey: "preferredVideoGender"),
           let gender = Gender(rawValue: saved) {
            preferredGender = gender
            return
        }
        
        if let userGender = UserDefaults.standard.string(forKey: "userGender") {
            preferredGender = userGender.lowercased().contains("female") ? .female : .male
            return
        }
        
        // Check current user
        if let user = UserManager.shared.currentUser,
           let gender = user.gender?.lowercased() {
            preferredGender = gender.contains("female") ? .female : .male
            UserDefaults.standard.set(preferredGender.rawValue, forKey: "preferredVideoGender")
        }
    }
    
    private func observeUserChanges() {
        // Observe user profile changes
        NotificationCenter.default.publisher(for: .userProfileUpdated)
            .sink { [weak self] _ in
                self?.loadGenderPreference()
            }
            .store(in: &cancellables)
    }
    
    private func loadExerciseGenderCache() {
        // Build cache from VideoStreamingService's gender cache
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let genderVideoCache = VideoStreamingService.shared.genderVideoCache
            
            var newCache: [String: ExerciseGenderInfo] = [:]
            
            for (key, genderInfo) in genderVideoCache {
                let info = ExerciseGenderInfo(
                    exerciseName: key,
                    hasMaleVersion: genderInfo.maleFilename != nil,
                    hasFemaleVersion: genderInfo.femaleFilename != nil,
                    maleVideoFilename: genderInfo.maleFilename,
                    femaleVideoFilename: genderInfo.femaleFilename
                )
                
                // Store under BOTH original key and normalized key for better matching
                newCache[key] = info
                
                // Also store under normalized key if different
                let normalizedKey = self.normalizeExerciseName(key)
                if normalizedKey != key {
                    newCache[normalizedKey] = info
                }
            }
            
            DispatchQueue.main.async {
                self.exerciseGenderCache = newCache
                self.cacheLoaded = true
                
                // 🔄 Clear video caches when gender cache is loaded/refreshed
                // This ensures videos match the current gender preference
                VideoPlaybackEngine.shared.clearAllCaches()
                
                #if DEBUG
                let maleOnly = newCache.values.filter { $0.hasMaleVersion && !$0.hasFemaleVersion }.count
                let femaleOnly = newCache.values.filter { $0.hasFemaleVersion && !$0.hasMaleVersion }.count
                let both = newCache.values.filter { $0.hasBothGenders }.count
                AppLogger.debug("👤 Gender cache loaded: \(newCache.count) exercises (including normalized keys)", category: .workout)
                AppLogger.debug("   Male only: \(maleOnly), Female only: \(femaleOnly), Both: \(both)", category: .workout)
                AppLogger.debug("👤 Video caches cleared to match gender preference", category: .workout)
                #endif
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let genderPreferenceChanged = Notification.Name("genderPreferenceChanged")
    static let userProfileUpdated = Notification.Name("userProfileUpdated")
}

// MARK: - VideoStreamingService Extension

extension VideoStreamingService {
    /// Get video URL using GenderFilterService's centralized preference
    func getGenderAwareVideoURL(for exerciseName: String) -> URL? {
        let preferred = GenderFilterService.shared.getPreferredGender()
        let videoGender: VideoGender = preferred == .female ? .female : .male
        return getVideoURL(for: exerciseName, gender: videoGender)
    }
}
