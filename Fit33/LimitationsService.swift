import Foundation
import SwiftUI
import Supabase

// MARK: - Limitation Models

/// Represents a user's physical limitation (injury, chronic condition, etc.)
struct UserLimitation: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let limitationType: LimitationType
    let affectedArea: AffectedArea
    let severity: Severity
    let exercisesToAvoid: [String]
    let movementPatternsToAvoid: [String]
    let equipmentToAvoid: [String]
    let notes: String?
    let startedDate: Date
    let expectedRecoveryDate: Date?
    let resolvedDate: Date?
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case limitationType = "limitation_type"
        case affectedArea = "affected_area"
        case severity
        case exercisesToAvoid = "exercises_to_avoid"
        case movementPatternsToAvoid = "movement_patterns_to_avoid"
        case equipmentToAvoid = "equipment_to_avoid"
        case notes
        case startedDate = "started_date"
        case expectedRecoveryDate = "expected_recovery_date"
        case resolvedDate = "resolved_date"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(id: UUID = UUID(), userId: UUID, limitationType: LimitationType, affectedArea: AffectedArea, severity: Severity, exercisesToAvoid: [String] = [], movementPatternsToAvoid: [String] = [], equipmentToAvoid: [String] = [], notes: String? = nil, startedDate: Date = Date(), expectedRecoveryDate: Date? = nil, resolvedDate: Date? = nil, isActive: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.limitationType = limitationType
        self.affectedArea = affectedArea
        self.severity = severity
        self.exercisesToAvoid = exercisesToAvoid
        self.movementPatternsToAvoid = movementPatternsToAvoid
        self.equipmentToAvoid = equipmentToAvoid
        self.notes = notes
        self.startedDate = startedDate
        self.expectedRecoveryDate = expectedRecoveryDate
        self.resolvedDate = resolvedDate
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Custom decoder to handle flexible date formats from Supabase
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        limitationType = try container.decode(LimitationType.self, forKey: .limitationType)
        affectedArea = try container.decode(AffectedArea.self, forKey: .affectedArea)
        severity = try container.decode(Severity.self, forKey: .severity)
        exercisesToAvoid = try container.decodeIfPresent([String].self, forKey: .exercisesToAvoid) ?? []
        movementPatternsToAvoid = try container.decodeIfPresent([String].self, forKey: .movementPatternsToAvoid) ?? []
        equipmentToAvoid = try container.decodeIfPresent([String].self, forKey: .equipmentToAvoid) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        
        // Flexible date parsing
        startedDate = try Self.decodeFlexibleDate(from: container, forKey: .startedDate) ?? Date()
        expectedRecoveryDate = try Self.decodeFlexibleDate(from: container, forKey: .expectedRecoveryDate)
        resolvedDate = try Self.decodeFlexibleDate(from: container, forKey: .resolvedDate)
        createdAt = try Self.decodeFlexibleDate(from: container, forKey: .createdAt) ?? Date()
        updatedAt = try Self.decodeFlexibleDate(from: container, forKey: .updatedAt) ?? Date()
    }
    
    // Helper to parse dates in multiple formats
    private static func decodeFlexibleDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        // Try as Date first
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }
        
        // Try as String
        guard let dateString = try? container.decode(String.self, forKey: key) else {
            return nil
        }
        
        // Empty string = nil
        if dateString.isEmpty {
            return nil
        }
        
        // Try ISO8601 with fractional seconds
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Try ISO8601 without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Try simple date format (2025-12-09)
        let simpleDateFormatter = Foundation.DateFormatter()
        simpleDateFormatter.dateFormat = "yyyy-MM-dd"
        simpleDateFormatter.timeZone = TimeZone(identifier: "UTC")
        if let date = simpleDateFormatter.date(from: dateString) {
            return date
        }
        
        // Try with time (2025-12-09 14:30:00)
        simpleDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = simpleDateFormatter.date(from: dateString) {
            return date
        }
        
        print("⚠️ [LIMITATIONS] Could not parse date: \(dateString)")
        return nil
    }
}

enum LimitationType: String, Codable, CaseIterable {
    case injury = "injury"
    case chronicCondition = "chronic_condition"
    case mobility = "mobility"
    case temporary = "temporary"
    
    var displayName: String {
        switch self {
        case .injury: return "Injury"
        case .chronicCondition: return "Chronic Condition"
        case .mobility: return "Mobility Issue"
        case .temporary: return "Temporary"
        }
    }
    
    var icon: String {
        switch self {
        case .injury: return "bandage.fill"
        case .chronicCondition: return "heart.text.square.fill"
        case .mobility: return "figure.walk.motion"
        case .temporary: return "clock.fill"
        }
    }
}

enum AffectedArea: String, Codable, CaseIterable, Identifiable {
    case lowerBack = "Lower Back"
    case upperBack = "Upper Back"
    case neck = "Neck"
    case leftShoulder = "Left Shoulder"
    case rightShoulder = "Right Shoulder"
    case shoulders = "Shoulders"
    case leftKnee = "Left Knee"
    case rightKnee = "Right Knee"
    case knees = "Knees"
    case leftHip = "Left Hip"
    case rightHip = "Right Hip"
    case hips = "Hips"
    case leftWrist = "Left Wrist"
    case rightWrist = "Right Wrist"
    case wrists = "Wrists"
    case leftElbow = "Left Elbow"
    case rightElbow = "Right Elbow"
    case elbows = "Elbows"
    case leftAnkle = "Left Ankle"
    case rightAnkle = "Right Ankle"
    case ankles = "Ankles"
    case core = "Core/Abdomen"
    case chest = "Chest"
    case pregnancy = "Pregnancy"
    case other = "Other"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .lowerBack, .upperBack: return "figure.stand"
        case .neck: return "person.crop.circle"
        case .leftShoulder, .rightShoulder, .shoulders: return "figure.arms.open"
        case .leftKnee, .rightKnee, .knees: return "figure.walk"
        case .leftHip, .rightHip, .hips: return "figure.stand"
        case .leftWrist, .rightWrist, .wrists: return "hand.raised.fill"
        case .leftElbow, .rightElbow, .elbows: return "hand.point.up.left.fill"
        case .leftAnkle, .rightAnkle, .ankles: return "shoe.fill"
        case .core: return "figure.core.training"
        case .chest: return "figure.strengthtraining.traditional"
        case .pregnancy: return "heart.circle.fill"
        case .other: return "questionmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .lowerBack, .upperBack: return .orange
        case .neck: return .purple
        case .leftShoulder, .rightShoulder, .shoulders: return .blue
        case .leftKnee, .rightKnee, .knees: return .red
        case .leftHip, .rightHip, .hips: return .pink
        case .leftWrist, .rightWrist, .wrists: return .cyan
        case .leftElbow, .rightElbow, .elbows: return .indigo
        case .leftAnkle, .rightAnkle, .ankles: return .teal
        case .core: return .yellow
        case .chest: return .mint
        case .pregnancy: return .pink
        case .other: return .gray
        }
    }
    
    /// Simplified area for mapping (combines left/right)
    var normalizedArea: String {
        switch self {
        case .leftShoulder, .rightShoulder, .shoulders: return "Shoulder"
        case .leftKnee, .rightKnee, .knees: return "Knee"
        case .leftHip, .rightHip, .hips: return "Hip"
        case .leftWrist, .rightWrist, .wrists: return "Wrist"
        case .leftElbow, .rightElbow, .elbows: return "Elbow"
        case .leftAnkle, .rightAnkle, .ankles: return "Ankle"
        case .lowerBack: return "Lower Back"
        case .upperBack: return "Upper Back"
        default: return rawValue
        }
    }
    
    /// Common areas shown during onboarding (simplified selection)
    static var commonAreas: [AffectedArea] {
        [.lowerBack, .shoulders, .knees, .hips, .neck, .wrists, .elbows, .ankles, .pregnancy, .other]
    }
}

/// User-friendly accommodation levels that tell the app what exercises are OK
enum AccommodationLevel: String, Codable, CaseIterable, Identifiable {
    case avoidCompletely = "avoid_completely"      // Skip ALL exercises for this area
    case lightOnly = "light_only"                   // Light/isolation work OK, skip heavy compound
    case stretchingOnly = "stretching_only"         // Only stretching/mobility exercises
    case beCareful = "be_careful"                   // Can do exercises, but recommend less & be careful
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .avoidCompletely: return "Skip completely"
        case .lightOnly: return "Light work only"
        case .stretchingOnly: return "Stretching only"
        case .beCareful: return "Be careful"
        }
    }
    
    var description: String {
        switch self {
        case .avoidCompletely: return "Don't recommend any exercises for this area"
        case .lightOnly: return "Light exercises OK, skip heavy compound movements"
        case .stretchingOnly: return "Only stretching and mobility work"
        case .beCareful: return "Can do exercises, just be more careful"
        }
    }
    
    var icon: String {
        switch self {
        case .avoidCompletely: return "xmark.circle.fill"
        case .lightOnly: return "wind"
        case .stretchingOnly: return "figure.flexibility"
        case .beCareful: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .avoidCompletely: return .red
        case .lightOnly: return .orange
        case .stretchingOnly: return .blue
        case .beCareful: return .yellow
        }
    }
    
    /// How much to penalize exercises for this area (higher = more penalized)
    var scorePenalty: Int {
        switch self {
        case .avoidCompletely: return 1000  // Effectively filter out
        case .lightOnly: return 100          // Heavy penalty on compound
        case .stretchingOnly: return 500     // Only allow stretching
        case .beCareful: return 30           // Small penalty, reduce frequency
        }
    }
    
    /// Whether to completely exclude exercises vs just penalize
    var shouldExclude: Bool {
        switch self {
        case .avoidCompletely: return true
        case .stretchingOnly: return false  // Special handling
        case .lightOnly: return false        // Special handling for compound
        case .beCareful: return false
        }
    }
}

// Keep Severity as an alias for backward compatibility with database
typealias Severity = AccommodationLevel

/// Mapping between limitations and exercises to avoid
struct LimitationExerciseMapping: Codable {
    let id: UUID
    let affectedArea: String
    let exerciseName: String
    let severityThreshold: String
    let reason: String?
    let alternativeExercises: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case affectedArea = "affected_area"
        case exerciseName = "exercise_name"
        case severityThreshold = "severity_threshold"
        case reason
        case alternativeExercises = "alternative_exercises"
    }
}

// MARK: - Limitations Service

@MainActor
class LimitationsService: ObservableObject {
    static let shared = LimitationsService()
    
    @Published var userLimitations: [UserLimitation] = []
    @Published var isLoading = false
    @Published var exerciseMappings: [LimitationExerciseMapping] = []
    
    // Using nonisolated(unsafe) for thread-safe cached data that's read from any context
    nonisolated(unsafe) private var cachedExercisesToAvoid: Set<String> = []
    nonisolated(unsafe) private var cachedMovementPatternsToAvoid: Set<String> = []
    nonisolated(unsafe) private var cachedLimitationsSnapshot: [UserLimitation] = []
    nonisolated(unsafe) private var cachedMappingsSnapshot: [LimitationExerciseMapping] = []
    
    private init() {
        Task {
            await loadExerciseMappings()
        }
    }
    
    // MARK: - Public API
    
    /// Fetch user's active limitations from cloud
    func fetchUserLimitations() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [LIMITATIONS] No user ID available")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response: [UserLimitation] = try await SupabaseManager.shared.supabaseClient
                .from("user_limitations")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("is_active", value: true)
                .execute()
                .value
            
            self.userLimitations = response
            updateCachedExercises()
            print("✅ [LIMITATIONS] Loaded \(response.count) active limitations")
        } catch {
            print("❌ [LIMITATIONS] Failed to fetch: \(error)")
        }
    }
    
    /// Add a new limitation
    func addLimitation(_ limitation: UserLimitation) async throws {
        let dto: [String: AnyJSON] = [
            "id": .string(limitation.id.uuidString),
            "user_id": .string(limitation.userId.uuidString),
            "limitation_type": .string(limitation.limitationType.rawValue),
            "affected_area": .string(limitation.affectedArea.rawValue),
            "severity": .string(limitation.severity.rawValue),
            "exercises_to_avoid": .array(limitation.exercisesToAvoid.map { .string($0) }),
            "movement_patterns_to_avoid": .array(limitation.movementPatternsToAvoid.map { .string($0) }),
            "equipment_to_avoid": .array(limitation.equipmentToAvoid.map { .string($0) }),
            "notes": limitation.notes.map { .string($0) } ?? .null,
            "started_date": .string(formatDate(limitation.startedDate)),
            "expected_recovery_date": limitation.expectedRecoveryDate.map { .string(formatDate($0)) } ?? .null,
            "is_active": .bool(limitation.isActive)
        ]
        
        try await SupabaseManager.shared.supabaseClient
            .from("user_limitations")
            .insert(dto)
            .execute()
        
        userLimitations.append(limitation)
        updateCachedExercises()
        print("✅ [LIMITATIONS] Added limitation for \(limitation.affectedArea.rawValue)")
    }
    
    /// Add multiple limitations at once (for onboarding)
    func addLimitations(_ limitations: [UserLimitation]) async throws {
        guard !limitations.isEmpty else { return }
        
        let dtos: [[String: AnyJSON]] = limitations.map { limitation in
            [
                "id": .string(limitation.id.uuidString),
                "user_id": .string(limitation.userId.uuidString),
                "limitation_type": .string(limitation.limitationType.rawValue),
                "affected_area": .string(limitation.affectedArea.rawValue),
                "severity": .string(limitation.severity.rawValue),
                "exercises_to_avoid": .array(limitation.exercisesToAvoid.map { .string($0) }),
                "movement_patterns_to_avoid": .array(limitation.movementPatternsToAvoid.map { .string($0) }),
                "equipment_to_avoid": .array(limitation.equipmentToAvoid.map { .string($0) }),
                "notes": limitation.notes.map { .string($0) } ?? .null,
                "started_date": .string(formatDate(limitation.startedDate)),
                "expected_recovery_date": limitation.expectedRecoveryDate.map { .string(formatDate($0)) } ?? .null,
                "is_active": .bool(limitation.isActive)
            ]
        }
        
        try await SupabaseManager.shared.supabaseClient
            .from("user_limitations")
            .insert(dtos)
            .execute()
        
        userLimitations.append(contentsOf: limitations)
        updateCachedExercises()
        print("✅ [LIMITATIONS] Added \(limitations.count) limitations")
    }
    
    /// Update an existing limitation
    func updateLimitation(_ limitation: UserLimitation) async throws {
        let dto: [String: AnyJSON] = [
            "limitation_type": .string(limitation.limitationType.rawValue),
            "affected_area": .string(limitation.affectedArea.rawValue),
            "severity": .string(limitation.severity.rawValue),
            "exercises_to_avoid": .array(limitation.exercisesToAvoid.map { .string($0) }),
            "movement_patterns_to_avoid": .array(limitation.movementPatternsToAvoid.map { .string($0) }),
            "equipment_to_avoid": .array(limitation.equipmentToAvoid.map { .string($0) }),
            "notes": limitation.notes.map { .string($0) } ?? .null,
            "expected_recovery_date": limitation.expectedRecoveryDate.map { .string(formatDate($0)) } ?? .null,
            "is_active": .bool(limitation.isActive)
        ]
        
        try await SupabaseManager.shared.supabaseClient
            .from("user_limitations")
            .update(dto)
            .eq("id", value: limitation.id.uuidString)
            .execute()
        
        if let index = userLimitations.firstIndex(where: { $0.id == limitation.id }) {
            userLimitations[index] = limitation
        }
        updateCachedExercises()
        print("✅ [LIMITATIONS] Updated limitation \(limitation.id)")
    }
    
    /// Mark a limitation as resolved (recovered)
    func resolveLimitation(_ limitation: UserLimitation) async throws {
        let dto: [String: AnyJSON] = [
            "is_active": .bool(false),
            "resolved_date": .string(formatDate(Date()))
        ]
        
        try await SupabaseManager.shared.supabaseClient
            .from("user_limitations")
            .update(dto)
            .eq("id", value: limitation.id.uuidString)
            .execute()
        
        userLimitations.removeAll { $0.id == limitation.id }
        updateCachedExercises()
        print("✅ [LIMITATIONS] Resolved limitation \(limitation.id)")
    }
    
    /// Delete a limitation completely
    func deleteLimitation(_ limitation: UserLimitation) async throws {
        try await SupabaseManager.shared.supabaseClient
            .from("user_limitations")
            .delete()
            .eq("id", value: limitation.id.uuidString)
            .execute()
        
        userLimitations.removeAll { $0.id == limitation.id }
        updateCachedExercises()
        print("✅ [LIMITATIONS] Deleted limitation \(limitation.id)")
    }
    
    // MARK: - Exercise Safety Filtering (nonisolated for cross-context access)
    
    /// Check if an exercise is safe for the user (can be called from any context)
    nonisolated func isExerciseSafe(_ exerciseName: String) -> Bool {
        let normalizedName = exerciseName.lowercased()
        
        // Check direct exclusions from cached set
        if cachedExercisesToAvoid.contains(where: { normalizedName.contains($0.lowercased()) }) {
            return false
        }
        
        // Check each limitation with its accommodation level
        for limitation in cachedLimitationsSnapshot {
            // Get the muscles/areas this exercise targets
            let exerciseTargetsArea = doesExerciseTargetArea(exerciseName: normalizedName, area: limitation.affectedArea)
            
            guard exerciseTargetsArea else { continue }
            
            // Apply accommodation level filtering
            switch limitation.severity {
            case .avoidCompletely:
                // User wants to skip ALL exercises for this area
                return false
                
            case .stretchingOnly:
                // Only allow if it's a stretching exercise
                let isStretch = normalizedName.contains("stretch") || 
                               normalizedName.contains("mobility") ||
                               normalizedName.contains("foam roll")
                if !isStretch { return false }
                
            case .lightOnly:
                // Skip heavy compound movements for this area
                let isHeavyCompound = isHeavyCompoundExercise(exerciseName: normalizedName)
                if isHeavyCompound { return false }
                
            case .beCareful:
                // Allow but the SmartExerciseSelectionEngine will penalize score
                break
            }
            
            // Also check against exercise mappings for specific exclusions
            let mappings = cachedMappingsSnapshot.filter { mapping in
                mapping.affectedArea.lowercased() == limitation.affectedArea.normalizedArea.lowercased()
            }
            
            for mapping in mappings {
                if normalizedName.contains(mapping.exerciseName.lowercased()) {
                    // If mapped to avoid and user chose avoid/light/stretch, exclude
                    if limitation.severity.shouldExclude {
                        return false
                    }
                }
            }
        }
        
        return true
    }
    
    /// Check if an exercise targets a specific body area
    /// Note: Bench press IS included for shoulders because it stresses the shoulder joint significantly
    nonisolated private func doesExerciseTargetArea(exerciseName: String, area: AffectedArea) -> Bool {
        let areaKeywords: [String: [String]] = [
            "Lower Back": ["deadlift", "good morning", "back extension", "hyperextension", "bent over", 
                          "rdl", "romanian", "stiff leg", "rack pull", "row"],
            "Upper Back": ["row", "pull up", "pullup", "chin up", "lat", "shrug", "face pull", "pulldown"],
            "Neck": ["shrug", "neck", "face pull", "upright row"],
            // Shoulders: Include bench press variations because they stress shoulder joint significantly
            "Shoulders": ["press", "shoulder", "delt", "raise", "fly", "overhead", "military", 
                         "arnold", "bench", "push up", "dip", "pike"],
            "Knees": ["squat", "lunge", "leg press", "leg extension", "leg curl", "step", 
                     "split squat", "pistol"],
            "Hips": ["squat", "deadlift", "hip", "glute", "lunge", "thrust", "bridge", 
                    "good morning", "abduct", "adduct"],
            "Wrists": ["curl", "wrist", "front squat", "clean", "snatch", "push up", "handstand"],
            "Elbows": ["curl", "extension", "tricep", "skull crusher", "pushdown", "dip", 
                      "close grip", "press"],
            "Ankles": ["calf", "jump", "hop", "sprint", "box jump", "skip", "run"],
            "Core/Abdomen": ["crunch", "sit up", "plank", "ab ", "core", "twist", "russian", 
                           "leg raise", "hollow", "v-up", "woodchop"],
            "Chest": ["bench", "chest", "fly", "push up", "pushup", "dip", "pec", "crossover", 
                     "incline", "decline"],
            "Pregnancy": ["crunch", "sit up", "twist", "russian", "leg raise", "v-up", "prone", 
                         "lying face down", "jump", "hop", "box jump", "burpee", "heavy squat", 
                         "heavy deadlift", "overhead press", "handstand", "inversion"]
        ]
        
        let normalizedArea = area.normalizedArea
        guard let keywords = areaKeywords[normalizedArea] else { return false }
        
        return keywords.contains { exerciseName.contains($0) }
    }
    
    /// Check if an exercise is a heavy compound movement
    nonisolated private func isHeavyCompoundExercise(exerciseName: String) -> Bool {
        let heavyCompounds = [
            // Deadlift variations
            "deadlift", "rdl", "romanian deadlift", "sumo deadlift", "stiff leg",
            // Squat variations
            "squat", "front squat", "back squat", "goblet squat", "hack squat",
            // Bench/Press variations (catches incline, decline, etc.)
            "bench press", "bench", "chest press", "incline press", "decline press",
            "overhead press", "military press", "shoulder press", "push press",
            // Row variations
            "barbell row", "bent over row", "pendlay row", "t-bar row",
            // Olympic lifts
            "clean", "snatch", "jerk", "power clean", "hang clean",
            // Other heavy compounds
            "hip thrust", "good morning", "leg press"
        ]
        
        return heavyCompounds.contains { exerciseName.contains($0) }
    }
    
    /// Get list of exercises to avoid (can be called from any context)
    nonisolated func getExercisesToAvoid() -> Set<String> {
        return cachedExercisesToAvoid
    }
    
    /// Get alternative exercises for a given exercise (can be called from any context)
    nonisolated func getAlternatives(for exerciseName: String) -> [String] {
        let normalizedName = exerciseName.lowercased()
        
        for mapping in cachedMappingsSnapshot {
            if normalizedName.contains(mapping.exerciseName.lowercased()) {
                return mapping.alternativeExercises ?? []
            }
        }
        
        return []
    }
    
    /// Sync version of shouldExclude for nonisolated access (now based on accommodation level)
    nonisolated private func shouldExcludeSync(accommodationLevel: AccommodationLevel) -> Bool {
        // Only completely exclude if user selected "avoid completely"
        return accommodationLevel == .avoidCompletely
    }
    
    /// Check if user has any active limitations
    var hasActiveLimitations: Bool {
        !userLimitations.isEmpty
    }
    
    /// Get summary of active limitations for display
    var limitationsSummary: String {
        if userLimitations.isEmpty {
            return "No active limitations"
        }
        
        let areas = userLimitations.map { $0.affectedArea.rawValue }
        if areas.count == 1 {
            return areas[0]
        } else if areas.count == 2 {
            return "\(areas[0]) & \(areas[1])"
        } else {
            return "\(areas.count) areas affected"
        }
    }
    
    // MARK: - Private Helpers
    
    private func loadExerciseMappings() async {
        do {
            let response: [LimitationExerciseMapping] = try await SupabaseManager.shared.supabaseClient
                .from("limitation_exercise_mappings")
                .select()
                .execute()
                .value
            
            exerciseMappings = response
            print("✅ [LIMITATIONS] Loaded \(response.count) exercise mappings")
        } catch {
            print("⚠️ [LIMITATIONS] Failed to load mappings, using defaults: \(error)")
            // Use built-in defaults if cloud fetch fails
            exerciseMappings = []
        }
    }
    
    private func updateCachedExercises() {
        var toAvoid = Set<String>()
        var patternsToAvoid = Set<String>()
        
        for limitation in userLimitations {
            toAvoid.formUnion(limitation.exercisesToAvoid)
            patternsToAvoid.formUnion(limitation.movementPatternsToAvoid)
            
            // Also add exercises from mappings
            let mappings = exerciseMappings.filter { mapping in
                mapping.affectedArea.lowercased() == limitation.affectedArea.normalizedArea.lowercased()
            }
            
            // For avoidCompletely, add all mapped exercises to avoid list
            if limitation.severity == .avoidCompletely {
                for mapping in mappings {
                    toAvoid.insert(mapping.exerciseName)
                }
            }
        }
        
        cachedExercisesToAvoid = toAvoid
        cachedMovementPatternsToAvoid = patternsToAvoid
        
        // Update snapshots for nonisolated access
        cachedLimitationsSnapshot = userLimitations
        cachedMappingsSnapshot = exerciseMappings
        
        print("🛡️ [SAFETY] Cached \(toAvoid.count) exercises to avoid")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}

// MARK: - Safety Filter for Exercise Selection

extension LimitationsService {
    
    /// Filter a list of exercises to only include safe ones
    /// Uses the new metadata-driven filtering system for comprehensive safety checks
    nonisolated func filterSafeExercises(_ exercises: [Exercise]) -> [Exercise] {
        guard hasActiveLimitationsSync else { 
            print("🛡️ [LIMITATIONS] No active limitations - all exercises safe")
            return exercises 
        }
        
        // Log active limitations
        let activeLimitations = cachedLimitationsSnapshot.filter { $0.isActive }
        if !activeLimitations.isEmpty {
            print("🛡️ [LIMITATIONS] Active limitations being applied:")
            for lim in activeLimitations {
                print("   • \(lim.affectedArea.rawValue): \(lim.severity.displayName)")
            }
        }
        
        // Use metadata-driven filtering for more comprehensive checks
        let filtered = exercises.filter { exercise in
            let exerciseName = exercise.name ?? ""
            
            // Quick check using legacy system
            if !isExerciseSafe(exerciseName) {
                return false
            }
            
            // Enhanced check using metadata classifier
            let metadata = ExerciseMetadataClassifier.shared.classify(exercise: exercise)
            
            for limitation in activeLimitations {
                let area = mapToLimitationArea(limitation.affectedArea)
                let severity = mapToLimitationSeverity(limitation.severity)
                
                // Check if exercise should be excluded based on metadata
                if shouldExcludeBasedOnMetadata(metadata: metadata, area: area, severity: severity) {
                    #if DEBUG
                    print("   🚫 [METADATA] Excluding '\(exerciseName)' for \(area.displayName)")
                    #endif
                    return false
                }
            }
            
            return true
        }
        
        let removedCount = exercises.count - filtered.count
        if removedCount > 0 {
            print("🛡️ [LIMITATIONS] Filtered out \(removedCount) unsafe exercises")
        }
        
        return filtered
    }
    
    /// Check if exercise should be excluded based on metadata and limitation
    nonisolated private func shouldExcludeBasedOnMetadata(
        metadata: ExerciseRiskMetadata,
        area: LimitationArea,
        severity: LimitationSeverity
    ) -> Bool {
        // For skip completely, use rule tables
        if severity == .skipCompletely {
            let rules = LimitationRuleTables.getSkipCompletelyRules(for: area)
            for rule in rules {
                if rule.matches(metadata) {
                    return true
                }
            }
        }
        
        // For stretching only, exclude non-stretch exercises
        if severity == .stretchingOnly {
            // Only check if the exercise affects the area
            if doesMetadataAffectArea(metadata: metadata, area: area) {
                return !metadata.isStretchOrMobility
            }
        }
        
        // For light work only, check exclusion rules
        if severity == .lightWorkOnly {
            let exclusionRules = LimitationRuleTables.getLightWorkExclusionRules(for: area)
            for rule in exclusionRules {
                if rule.matches(metadata) {
                    return true
                }
            }
        }
        
        // Be careful doesn't exclude, just penalizes during scoring
        return false
    }
    
    /// Check if metadata indicates the exercise affects a body area
    nonisolated private func doesMetadataAffectArea(metadata: ExerciseRiskMetadata, area: LimitationArea) -> Bool {
        switch area {
        case .lowerBack:
            return metadata.spinalLoad >= .moderate ||
                   metadata.axialLoading >= .low ||
                   metadata.unsupportedTorso ||
                   metadata.hipHingeDemand
        case .upperBack:
            return metadata.movementPatterns.contains(RiskMovementPattern.pull)
        case .shoulders:
            return !metadata.shoulderStressFlags.isEmpty ||
                   metadata.overheadWork != .none ||
                   metadata.movementPatterns.contains(RiskMovementPattern.push)
        case .knees:
            return metadata.kneeFlexionDepth >= .moderate ||
                   metadata.impactLevel >= .moderate
        case .hips:
            return metadata.hipHingeDemand
        case .neck:
            return metadata.neckStress || metadata.axialLoading >= .high
        case .wrists:
            return metadata.wristExtensionDemand != .low
        case .elbows:
            return metadata.elbowStress
        case .ankles:
            return metadata.impactLevel >= .moderate || metadata.balanceDemand == .high
        case .pregnancy:
            // Avoid exercises with high impact, spinal load, prone positions, or twisting
            return metadata.impactLevel >= .moderate ||
                   metadata.spinalLoad >= .moderate ||
                   metadata.axialLoading == .high ||
                   metadata.overheadWork == .full ||
                   metadata.balanceDemand == .high
        case .other:
            return false
        }
    }
    
    /// Map AffectedArea to LimitationArea
    nonisolated private func mapToLimitationArea(_ area: AffectedArea) -> LimitationArea {
        switch area {
        case .lowerBack: return .lowerBack
        case .upperBack: return .upperBack
        case .neck: return .neck
        case .leftShoulder, .rightShoulder, .shoulders: return .shoulders
        case .leftKnee, .rightKnee, .knees: return .knees
        case .leftHip, .rightHip, .hips: return .hips
        case .leftWrist, .rightWrist, .wrists: return .wrists
        case .leftElbow, .rightElbow, .elbows: return .elbows
        case .leftAnkle, .rightAnkle, .ankles: return .ankles
        case .pregnancy: return .pregnancy
        case .core, .chest, .other: return .other
        }
    }
    
    /// Map AccommodationLevel to LimitationSeverity
    nonisolated private func mapToLimitationSeverity(_ severity: AccommodationLevel) -> LimitationSeverity {
        switch severity {
        case .avoidCompletely: return .skipCompletely
        case .lightOnly: return .lightWorkOnly
        case .stretchingOnly: return .stretchingOnly
        case .beCareful: return .beCareful
        }
    }
    
    /// Filter exercise names (nonisolated)
    nonisolated func filterSafeExerciseNames(_ names: [String]) -> [String] {
        guard hasActiveLimitationsSync else { return names }
        return names.filter { isExerciseSafe($0) }
    }
    
    /// Sync check for active limitations (nonisolated)
    nonisolated var hasActiveLimitationsSync: Bool {
        !cachedLimitationsSnapshot.isEmpty
    }
    
    /// Check if user has a lower back limitation (nonisolated for thread-safe access)
    /// Used by SmartExerciseSelectionEngine to apply lower back safety filtering
    nonisolated var hasLowerBackLimitation: Bool {
        cachedLimitationsSnapshot.contains { limitation in
            let area = limitation.affectedArea.rawValue.lowercased()
            return area.contains("lower back") || area.contains("low back") || area == "back"
        }
    }
    
    /// Get the safety penalty/boost for an exercise based on all active limitations
    /// Returns: negative = penalty (risky), positive = boost (safe), zero = neutral
    nonisolated func getSafetyPenalty(for exercise: Exercise) -> Double {
        guard hasActiveLimitationsSync else { return 0 }
        
        let metadata = ExerciseMetadataClassifier.shared.classify(exercise: exercise)
        var totalPenalty: Double = 0
        
        for limitation in cachedLimitationsSnapshot where limitation.isActive {
            let area = mapToLimitationArea(limitation.affectedArea)
            let severity = mapToLimitationSeverity(limitation.severity)
            
            // Only apply penalty if exercise affects the limitation area
            guard doesMetadataAffectArea(metadata: metadata, area: area) else { continue }
            
            // Get rules based on severity
            let rules: [LimitationRule]
            switch severity {
            case .skipCompletely:
                // Should have been filtered out already - but add heavy penalty just in case
                rules = LimitationRuleTables.getSkipCompletelyRules(for: area)
                for rule in rules where rule.matches(metadata) {
                    totalPenalty += 500
                }
                
            case .stretchingOnly:
                if !metadata.isStretchOrMobility {
                    totalPenalty += 300
                }
                
            case .lightWorkOnly:
                let exclusionRules = LimitationRuleTables.getLightWorkExclusionRules(for: area)
                for rule in exclusionRules where rule.matches(metadata) {
                    totalPenalty += 200
                }
                
                let preferenceRules = LimitationRuleTables.getLightWorkPreferenceRules(for: area)
                for rule in preferenceRules where rule.matches(metadata) {
                    if rule.isNegative {
                        totalPenalty += rule.penalty
                    } else {
                        totalPenalty -= rule.penalty  // Boost (negative penalty)
                    }
                }
                
            case .beCareful:
                let beCarefulRules = LimitationRuleTables.getBeCarefulRules(for: area)
                for rule in beCarefulRules where rule.matches(metadata) {
                    if rule.isNegative {
                        totalPenalty += rule.penalty
                    } else {
                        totalPenalty -= rule.penalty  // Boost
                    }
                }
            }
        }
        
        return totalPenalty
    }
    
    /// Get warning tags for an exercise based on limitations
    nonisolated func getWarningTags(for exercise: Exercise) -> [String] {
        guard hasActiveLimitationsSync else { return [] }
        
        let metadata = ExerciseMetadataClassifier.shared.classify(exercise: exercise)
        var warnings: [String] = []
        
        for limitation in cachedLimitationsSnapshot where limitation.isActive {
            let area = mapToLimitationArea(limitation.affectedArea)
            let severity = mapToLimitationSeverity(limitation.severity)
            
            guard doesMetadataAffectArea(metadata: metadata, area: area) else { continue }
            
            if severity == .beCareful || severity == .lightWorkOnly {
                // Add appropriate warning
                if metadata.isMachineSupported || metadata.isChestSupported {
                    warnings.append("✅ Safe for \(area.displayName)")
                } else {
                    warnings.append("⚠️ Use caution for \(area.displayName)")
                }
            }
        }
        
        return warnings
    }
}

