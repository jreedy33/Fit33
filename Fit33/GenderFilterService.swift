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
        print("👤 GenderFilterService initialized - preference: \(preferredGender.rawValue)")
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
        
        #if DEBUG
        print("👤 Gender preference updated to: \(gender.rawValue)")
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
            // No gender info cached - show exercise (might not have gender data)
            return true
        }
        
        // If exercise has preferred gender version, show it
        if info.isAvailable(for: preferredGender) {
            return true
        }
        
        // If exercise ONLY exists for opposite gender, still show it (fallback)
        if info.isAvailable(for: preferredGender.opposite) && !info.hasBothGenders {
            return true
        }
        
        // Exercise exists for both genders but preferred not available - shouldn't happen
        // but return true as safety
        return true
    }
    
    /// Get the correct video filename for an exercise based on gender
    func getVideoFilename(for exerciseName: String, fallbackToOpposite: Bool = true) -> String? {
        let key = exerciseName.lowercased()
        
        guard let info = exerciseGenderCache[key] else {
            return nil
        }
        
        return info.videoFilename(for: preferredGender, withFallback: fallbackToOpposite)
    }
    
    /// Check if exercise has video for preferred gender (vs fallback)
    func hasPreferredGenderVideo(for exerciseName: String) -> Bool {
        let key = exerciseName.lowercased()
        guard let info = exerciseGenderCache[key] else { return false }
        return info.isAvailable(for: preferredGender)
    }
    
    /// Filter a list of exercises to show only appropriate ones
    /// This is the main filtering function used by views
    func filterExercises(_ exercises: [Exercise]) -> [Exercise] {
        // For now, show all exercises since videos handle gender fallback
        // In future, could hide exercises without any video for user's gender
        return exercises
    }
    
    /// Filter generated exercises by gender availability
    func filterGeneratedExercises(_ exercises: [GeneratedExercise]) -> [GeneratedExercise] {
        return exercises
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
                newCache[key] = ExerciseGenderInfo(
                    exerciseName: key,
                    hasMaleVersion: genderInfo.maleFilename != nil,
                    hasFemaleVersion: genderInfo.femaleFilename != nil,
                    maleVideoFilename: genderInfo.maleFilename,
                    femaleVideoFilename: genderInfo.femaleFilename
                )
            }
            
            DispatchQueue.main.async {
                self.exerciseGenderCache = newCache
                self.cacheLoaded = true
                
                #if DEBUG
                let maleOnly = newCache.values.filter { $0.hasMaleVersion && !$0.hasFemaleVersion }.count
                let femaleOnly = newCache.values.filter { $0.hasFemaleVersion && !$0.hasMaleVersion }.count
                let both = newCache.values.filter { $0.hasBothGenders }.count
                print("👤 Gender cache loaded: \(newCache.count) exercises")
                print("   Male only: \(maleOnly), Female only: \(femaleOnly), Both: \(both)")
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
