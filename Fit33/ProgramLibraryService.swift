import Foundation
import SwiftUI

// MARK: - Enhanced Program Models

/// Location type for program - determines equipment requirements
enum ProgramLocation: String, CaseIterable, Codable {
    case gym = "Gym"
    case home = "Home"
    case hybrid = "Hybrid"  // Can be done at gym or home
    case outdoor = "Outdoor"
    case minimal = "Minimal Equipment"
    
    var icon: String {
        switch self {
        case .gym: return "building.2.fill"
        case .home: return "house.fill"
        case .hybrid: return "arrow.left.arrow.right"
        case .outdoor: return "sun.max.fill"
        case .minimal: return "figure.walk"
        }
    }
    
    var description: String {
        switch self {
        case .gym: return "Full gym equipment required"
        case .home: return "Home equipment only"
        case .hybrid: return "Works at gym or home"
        case .outdoor: return "Outdoor/park workouts"
        case .minimal: return "Bodyweight + minimal gear"
        }
    }
}

/// Program duration category for filtering
enum ProgramDuration: String, CaseIterable, Codable {
    case oneWeek = "1 Week"
    case twoWeeks = "2 Weeks"
    case oneMonth = "4 Weeks"
    case sixWeeks = "6 Weeks"
    case twoMonths = "8 Weeks"
    case threeMonths = "12 Weeks"
    case fourMonths = "16 Weeks"
    
    var days: Int {
        switch self {
        case .oneWeek: return 7
        case .twoWeeks: return 14
        case .oneMonth: return 28
        case .sixWeeks: return 42
        case .twoMonths: return 56
        case .threeMonths: return 84
        case .fourMonths: return 112
        }
    }
    
    var shortName: String {
        switch self {
        case .oneWeek: return "1W"
        case .twoWeeks: return "2W"
        case .oneMonth: return "4W"
        case .sixWeeks: return "6W"
        case .twoMonths: return "8W"
        case .threeMonths: return "12W"
        case .fourMonths: return "16W"
        }
    }
}

/// Program goal/focus for filtering
enum ProgramGoal: String, CaseIterable, Codable {
    case buildMuscle = "Build Muscle"
    case loseWeight = "Lose Weight"
    case gainStrength = "Gain Strength"
    case improveEndurance = "Improve Endurance"
    case toneUp = "Tone & Define"
    case athletic = "Athletic Performance"
    case flexibility = "Flexibility & Mobility"
    case generalFitness = "General Fitness"
    case powerlifting = "Powerlifting"
    case bodybuilding = "Bodybuilding"
    
    var icon: String {
        switch self {
        case .buildMuscle: return "figure.strengthtraining.traditional"
        case .loseWeight: return "flame.fill"
        case .gainStrength: return "scalemass.fill"
        case .improveEndurance: return "heart.fill"
        case .toneUp: return "figure.mixed.cardio"
        case .athletic: return "figure.run"
        case .flexibility: return "figure.yoga"
        case .generalFitness: return "figure.walk"
        case .powerlifting: return "dumbbell.fill"
        case .bodybuilding: return "figure.arms.open"
        }
    }
    
    static func fromUserGoalString(_ goal: String) -> ProgramGoal {
        switch goal.lowercased() {
        case "strength", "get stronger":        return .gainStrength
        case "bulk", "build muscle", "muscle":  return .buildMuscle
        case "cut", "lose weight", "fat loss":  return .loseWeight
        case "tone", "toning", "define":        return .toneUp
        case "cardio", "endurance":             return .improveEndurance
        case "powerlifting":                    return .powerlifting
        case "bodybuilding":                    return .bodybuilding
        case "athletic", "athletic performance": return .athletic
        case "flexibility", "mobility":         return .flexibility
        default:                                return .generalFitness
        }
    }
}

/// Days per week options
enum WorkoutFrequency: Int, CaseIterable, Codable {
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    
    var displayName: String {
        return "\(rawValue) days/week"
    }
}

/// Training split type
enum TrainingSplit: String, CaseIterable, Codable {
    case fullBody = "Full Body"
    case upperLower = "Upper/Lower"
    case pushPullLegs = "Push/Pull/Legs"
    case bro = "Bro Split"
    case arnoldSplit = "Arnold Split"
    case phat = "PHAT"
    case phul = "PHUL"
    case custom = "Custom Split"
    
    var description: String {
        switch self {
        case .fullBody: return "Train whole body each session"
        case .upperLower: return "Alternate upper and lower body"
        case .pushPullLegs: return "Push, pull, and legs rotation"
        case .bro: return "One muscle group per day"
        case .arnoldSplit: return "Chest/Back, Shoulders/Arms, Legs"
        case .phat: return "Power + Hypertrophy training"
        case .phul: return "Power Hypertrophy Upper Lower"
        case .custom: return "Unique training structure"
        }
    }
}

// MARK: - Extended Program Model

struct ExtendedProgram: Identifiable, Codable {
    let id: String
    let name: String
    let subtitle: String
    let description: String
    let duration: ProgramDuration
    let difficulty: ProgramDifficulty
    let location: ProgramLocation
    let goals: [ProgramGoal]
    let frequency: WorkoutFrequency
    let split: TrainingSplit
    let equipment: [String]
    let icon: String
    let gradientColors: [String]  // Hex colors for gradient
    let workoutsPerWeek: Int
    let avgWorkoutMinutes: Int
    let benefits: [String]
    let preview: String
    let tags: [String]
    let popularityScore: Int  // 0-100
    let isFeatured: Bool
    let isNew: Bool
    
    // Computed properties
    var durationDays: Int { duration.days }
    
    var primaryGoal: ProgramGoal {
        goals.first ?? .generalFitness
    }
    
    var gradientSwiftUIColors: [Color] {
        gradientColors.map { Color(hex: $0) ?? .blue }
    }
}

// MARK: - Program Library Service

class ProgramLibraryService: ObservableObject {
    static let shared = ProgramLibraryService()
    
    @Published var allPrograms: [ExtendedProgram] = []
    @Published var isLoading = false
    
    private init() {
        loadPrograms()
    }
    
    // MARK: - Load Programs
    
    func loadPrograms() {
        allPrograms = generateComprehensiveProgramLibrary()
    }
    
    // MARK: - Filtering
    
    func filterPrograms(
        difficulty: ProgramDifficulty? = nil,
        location: ProgramLocation? = nil,
        goal: ProgramGoal? = nil,
        duration: ProgramDuration? = nil,
        frequency: WorkoutFrequency? = nil,
        split: TrainingSplit? = nil,
        equipment: [String]? = nil,
        searchText: String = ""
    ) -> [ExtendedProgram] {
        var filtered = allPrograms
        
        if let difficulty = difficulty {
            filtered = filtered.filter { $0.difficulty == difficulty }
        }
        
        if let location = location {
            filtered = filtered.filter { $0.location == location }
        }
        
        if let goal = goal {
            filtered = filtered.filter { $0.goals.contains(goal) }
        }
        
        if let duration = duration {
            filtered = filtered.filter { $0.duration == duration }
        }
        
        if let frequency = frequency {
            filtered = filtered.filter { $0.frequency == frequency }
        }
        
        if let split = split {
            filtered = filtered.filter { $0.split == split }
        }
        
        if let equipment = equipment, !equipment.isEmpty {
            filtered = filtered.filter { program in
                // Program equipment should be subset of available equipment
                Set(program.equipment.map { $0.lowercased() })
                    .isSubset(of: Set(equipment.map { $0.lowercased() }))
            }
        }
        
        if !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            filtered = filtered.filter { program in
                program.name.lowercased().contains(lowercased) ||
                program.subtitle.lowercased().contains(lowercased) ||
                program.description.lowercased().contains(lowercased) ||
                program.tags.contains { $0.lowercased().contains(lowercased) }
            }
        }
        
        return filtered.sorted { $0.popularityScore > $1.popularityScore }
    }
    
    // MARK: - Smart Recommendations
    
    // TODO: Delegate to SmartProgramRecommender.shared for unified recommendation logic
    func getRecommendedPrograms(
        forExperience experience: String,
        goal: String,
        availableDays: Int,
        equipment: [String],
        limit: Int = 5
    ) -> [ExtendedProgram] {
        // Map experience string to difficulty
        let difficulty: ProgramDifficulty
        switch experience.lowercased() {
        case "beginner": difficulty = .beginner
        case "advanced": difficulty = .advanced
        default: difficulty = .intermediate
        }
        
        // Map goal string to ProgramGoal
        let programGoal: ProgramGoal
        switch goal.lowercased() {
        case "build muscle", "bulk": programGoal = .buildMuscle
        case "lose weight", "cut": programGoal = .loseWeight
        case "strength": programGoal = .gainStrength
        case "endurance", "cardio": programGoal = .improveEndurance
        case "tone", "toning": programGoal = .toneUp
        default: programGoal = .generalFitness
        }
        
        // Map available days to frequency
        let frequency: WorkoutFrequency
        switch availableDays {
        case 2: frequency = .two
        case 3: frequency = .three
        case 4: frequency = .four
        case 5: frequency = .five
        case 6: frequency = .six
        case 7: frequency = .seven
        default: frequency = .four
        }
        
        // Determine location based on equipment
        let hasGymEquipment = equipment.contains { 
            ["barbell", "machines", "cables", "smith machine"].contains($0.lowercased())
        }
        let location: ProgramLocation? = hasGymEquipment ? .gym : .home
        
        // Score and rank programs
        let scoredPrograms = allPrograms.map { program -> (ExtendedProgram, Int) in
            var score = 0
            
            // Difficulty match (most important)
            if program.difficulty == difficulty { score += 30 }
            else if abs(ProgramDifficulty.allCases.firstIndex(of: program.difficulty)! - 
                       ProgramDifficulty.allCases.firstIndex(of: difficulty)!) == 1 { score += 15 }
            
            // Goal match
            if program.goals.contains(programGoal) { score += 25 }
            if program.primaryGoal == programGoal { score += 10 }
            
            // Frequency match
            if program.frequency == frequency { score += 20 }
            else if abs(program.frequency.rawValue - frequency.rawValue) == 1 { score += 10 }
            
            // Location match
            if let loc = location {
                if program.location == loc { score += 15 }
                else if program.location == .hybrid { score += 10 }
            }
            
            // Equipment compatibility
            let programEquipmentSet = Set(program.equipment.map { $0.lowercased() })
            let userEquipmentSet = Set(equipment.map { $0.lowercased() })
            if programEquipmentSet.isSubset(of: userEquipmentSet) { score += 15 }
            
            // Popularity bonus
            score += program.popularityScore / 10
            
            // Featured bonus
            if program.isFeatured { score += 5 }
            
            return (program, score)
        }
        
        return scoredPrograms
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    // MARK: - Generate Program Library (100 Programs)
    
    private func generateComprehensiveProgramLibrary() -> [ExtendedProgram] {
        var programs: [ExtendedProgram] = []
        
        // ========================================
        // BEGINNER PROGRAMS (25 programs)
        // ========================================
        
        // Full Body Beginner Programs
        programs.append(ExtendedProgram(
            id: "beg_fullbody_1w",
            name: "First Week Foundations",
            subtitle: "Your very first week of fitness",
            description: "A gentle introduction to weight training with simple, effective movements. Perfect for complete beginners.",
            duration: .oneWeek,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.generalFitness, .buildMuscle],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Bodyweight"],
            icon: "figure.walk",
            gradientColors: ["#4ECDC4", "#44A08D"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 30,
            benefits: ["Learn basic movement patterns", "Build workout habit", "Low risk of injury"],
            preview: "3 days of simple full-body workouts",
            tags: ["beginner", "starter", "foundation", "basics"],
            popularityScore: 95,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_fullbody_4w",
            name: "4-Week Beginner Blueprint",
            subtitle: "Master the fundamentals",
            description: "A comprehensive month-long program designed to teach proper form while building a solid fitness base.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .gym,
            goals: [.generalFitness, .buildMuscle, .gainStrength],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Barbell", "Cables"],
            icon: "chart.line.uptrend.xyaxis",
            gradientColors: ["#667eea", "#764ba2"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 45,
            benefits: ["Progressive overload introduction", "Form mastery", "Strength foundation"],
            preview: "Structured progression over 4 weeks",
            tags: ["beginner", "foundation", "progressive", "gym"],
            popularityScore: 92,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_home_4w",
            name: "Home Starter Program",
            subtitle: "No gym? No problem!",
            description: "Build strength and fitness using only dumbbells and bodyweight exercises. Perfect for home workouts.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .home,
            goals: [.generalFitness, .toneUp],
            frequency: .four,
            split: .fullBody,
            equipment: ["Dumbbells", "Bodyweight"],
            icon: "house.fill",
            gradientColors: ["#f093fb", "#f5576c"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 35,
            benefits: ["Convenient home workouts", "Minimal equipment", "Flexible scheduling"],
            preview: "4 weeks of effective home training",
            tags: ["home", "beginner", "minimal", "convenient"],
            popularityScore: 88,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_bodyweight_6w",
            name: "Bodyweight Basics",
            subtitle: "Build strength with zero equipment",
            description: "Master your own bodyweight with progressions from easy to challenging. No equipment required.",
            duration: .sixWeeks,
            difficulty: .beginner,
            location: .minimal,
            goals: [.gainStrength, .toneUp, .generalFitness],
            frequency: .four,
            split: .fullBody,
            equipment: ["Bodyweight"],
            icon: "figure.strengthtraining.functional",
            gradientColors: ["#11998e", "#38ef7d"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 40,
            benefits: ["Zero equipment needed", "Progressive difficulty", "Builds body awareness"],
            preview: "Push-ups to pistol squats in 6 weeks",
            tags: ["bodyweight", "calisthenics", "no equipment", "anywhere"],
            popularityScore: 85,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_strength_8w",
            name: "Strength Starter",
            subtitle: "Your first strength program",
            description: "Learn the big lifts: squat, bench, deadlift, and overhead press. Focus on form before weight.",
            duration: .twoMonths,
            difficulty: .beginner,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .three,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells", "Bench"],
            icon: "scalemass.fill",
            gradientColors: ["#ff6b6b", "#feca57"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 50,
            benefits: ["Master compound lifts", "Build real strength", "Solid foundation"],
            preview: "8 weeks of foundational strength work",
            tags: ["strength", "barbell", "compound", "powerlifting"],
            popularityScore: 82,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_fatburn_4w",
            name: "Beginner Fat Burner",
            subtitle: "Start your weight loss journey",
            description: "Combine strength training with high-rep circuits to maximize calorie burn while building muscle.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.loseWeight, .toneUp],
            frequency: .four,
            split: .fullBody,
            equipment: ["Dumbbells", "Bodyweight"],
            icon: "flame.fill",
            gradientColors: ["#f12711", "#f5af19"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 40,
            benefits: ["High calorie burn", "Muscle preservation", "Increased metabolism"],
            preview: "Burn fat while learning to lift",
            tags: ["fat loss", "weight loss", "cardio", "circuits"],
            popularityScore: 90,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_upperlower_4w",
            name: "Upper/Lower Introduction",
            subtitle: "Your first split routine",
            description: "Graduate from full body to a simple upper/lower split. Train 4 days per week.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .gym,
            goals: [.buildMuscle, .gainStrength],
            frequency: .four,
            split: .upperLower,
            equipment: ["Dumbbells", "Barbell", "Cables", "Machines"],
            icon: "arrow.up.arrow.down",
            gradientColors: ["#4facfe", "#00f2fe"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["Better recovery", "More volume per muscle", "Structured progression"],
            preview: "2 upper days + 2 lower days per week",
            tags: ["upper lower", "split", "4 day", "gym"],
            popularityScore: 78,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_mobility_2w",
            name: "Mobility Jumpstart",
            subtitle: "Move better in 2 weeks",
            description: "Improve flexibility and joint health before starting a lifting program. Great warm-up routine.",
            duration: .twoWeeks,
            difficulty: .beginner,
            location: .minimal,
            goals: [.flexibility, .generalFitness],
            frequency: .five,
            split: .fullBody,
            equipment: ["Bodyweight", "Resistance Bands"],
            icon: "figure.yoga",
            gradientColors: ["#a18cd1", "#fbc2eb"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 25,
            benefits: ["Improved flexibility", "Reduced injury risk", "Better posture"],
            preview: "Daily mobility flows for beginners",
            tags: ["mobility", "flexibility", "stretching", "recovery"],
            popularityScore: 72,
            isFeatured: false,
            isNew: false
        ))
        
        // ========================================
        // INTERMEDIATE PROGRAMS (40 programs)
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "int_ppl_8w",
            name: "Classic Push/Pull/Legs",
            subtitle: "The tried and true split",
            description: "The most popular intermediate split. Hit each muscle group twice per week for optimal growth.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .gainStrength],
            frequency: .six,
            split: .pushPullLegs,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "arrow.triangle.2.circlepath",
            gradientColors: ["#6366f1", "#8b5cf6"],
            workoutsPerWeek: 6,
            avgWorkoutMinutes: 60,
            benefits: ["Maximum frequency", "Balanced development", "Proven results"],
            preview: "Push, Pull, Legs - 6 days per week",
            tags: ["ppl", "hypertrophy", "bodybuilding", "6 day"],
            popularityScore: 98,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_ppl_12w",
            name: "PPL Mass Builder",
            subtitle: "12 weeks of serious gains",
            description: "An extended PPL program with periodization. Build serious muscle mass over 3 months.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .bodybuilding],
            frequency: .six,
            split: .pushPullLegs,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "chart.bar.fill",
            gradientColors: ["#ec4899", "#8b5cf6"],
            workoutsPerWeek: 6,
            avgWorkoutMinutes: 70,
            benefits: ["Periodized progression", "Maximum hypertrophy", "Detailed tracking"],
            preview: "3 phases of muscle building",
            tags: ["ppl", "mass", "periodization", "bodybuilding"],
            popularityScore: 94,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_upperlower_8w",
            name: "Power Upper/Lower",
            subtitle: "Strength meets hypertrophy",
            description: "Combine heavy compound lifts with hypertrophy work. Perfect balance of strength and size.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "bolt.fill",
            gradientColors: ["#f59e0b", "#ef4444"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 65,
            benefits: ["Strength gains", "Muscle growth", "Efficient 4-day split"],
            preview: "Heavy days + volume days",
            tags: ["upper lower", "strength", "hypertrophy", "4 day"],
            popularityScore: 91,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_phul_12w",
            name: "PHUL Program",
            subtitle: "Power Hypertrophy Upper Lower",
            description: "Layne Norton's famous program. Power days for strength, hypertrophy days for size.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .buildMuscle, .powerlifting],
            frequency: .four,
            split: .phul,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "flame.circle.fill",
            gradientColors: ["#dc2626", "#f97316"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 70,
            benefits: ["Best of both worlds", "Research-backed", "Flexible scheduling"],
            preview: "2 power + 2 hypertrophy days",
            tags: ["phul", "powerbuilding", "proven", "layne norton"],
            popularityScore: 89,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_arnold_8w",
            name: "Arnold Split",
            subtitle: "Train like the legend",
            description: "The classic Arnold Schwarzenegger split: Chest/Back, Shoulders/Arms, Legs. High volume approach.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .bodybuilding],
            frequency: .six,
            split: .arnoldSplit,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "star.fill",
            gradientColors: ["#fbbf24", "#f59e0b"],
            workoutsPerWeek: 6,
            avgWorkoutMinutes: 75,
            benefits: ["High volume", "Classic physique", "Golden era training"],
            preview: "6 days of old-school bodybuilding",
            tags: ["arnold", "bodybuilding", "classic", "volume"],
            popularityScore: 86,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_brosplit_8w",
            name: "Classic Bro Split",
            subtitle: "One muscle group per day",
            description: "The traditional bodybuilding split. Destroy each muscle group once per week with maximum volume.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .bodybuilding],
            frequency: .five,
            split: .bro,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "person.fill",
            gradientColors: ["#3b82f6", "#1d4ed8"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 65,
            benefits: ["Maximum volume per muscle", "Full recovery", "Simple to follow"],
            preview: "Chest, Back, Shoulders, Arms, Legs",
            tags: ["bro split", "bodybuilding", "5 day", "volume"],
            popularityScore: 83,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_strength_12w",
            name: "Intermediate Strength",
            subtitle: "Get seriously strong",
            description: "A 12-week linear progression program focused on the big 3 lifts. Add weight every week.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .powerlifting],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Power Rack", "Bench"],
            icon: "scalemass.fill",
            gradientColors: ["#7c3aed", "#4f46e5"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 60,
            benefits: ["Consistent PRs", "Structured progression", "Strength focus"],
            preview: "12 weeks of progressive overload",
            tags: ["strength", "powerlifting", "linear", "progressive"],
            popularityScore: 87,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_cut_8w",
            name: "Intermediate Shred",
            subtitle: "Lose fat, keep muscle",
            description: "A cutting program designed to preserve muscle while dropping body fat. Higher frequency, moderate volume.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.loseWeight, .toneUp],
            frequency: .five,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "flame.fill",
            gradientColors: ["#ef4444", "#dc2626"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 55,
            benefits: ["Fat loss", "Muscle retention", "Metabolic boost"],
            preview: "Shred down over 8 weeks",
            tags: ["cutting", "shred", "fat loss", "lean"],
            popularityScore: 88,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_home_8w",
            name: "Home Gym Warrior",
            subtitle: "Serious gains at home",
            description: "A complete program for home gym owners with dumbbells and a bench. No cables or machines needed.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .home,
            goals: [.buildMuscle, .gainStrength],
            frequency: .five,
            split: .upperLower,
            equipment: ["Dumbbells", "Bench", "Bodyweight"],
            icon: "house.fill",
            gradientColors: ["#10b981", "#059669"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 50,
            benefits: ["Home convenience", "Effective workouts", "No gym needed"],
            preview: "5 days of home training excellence",
            tags: ["home", "dumbbells", "minimal", "effective"],
            popularityScore: 84,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_fullbody_6w",
            name: "Full Body Frequency",
            subtitle: "Hit every muscle 3x/week",
            description: "High frequency full body training. Perfect for natural lifters who want to maximize protein synthesis.",
            duration: .sixWeeks,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .generalFitness],
            frequency: .three,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "figure.strengthtraining.traditional",
            gradientColors: ["#14b8a6", "#0d9488"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 60,
            benefits: ["High frequency", "More recovery days", "Time efficient"],
            preview: "Full body workouts, 3x per week",
            tags: ["full body", "frequency", "natural", "efficient"],
            popularityScore: 79,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_athletic_8w",
            name: "Athletic Performance",
            subtitle: "Train like an athlete",
            description: "Combine strength, power, and conditioning for overall athletic development.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.athletic, .gainStrength, .improveEndurance],
            frequency: .five,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Kettlebells", "Bodyweight"],
            icon: "figure.run",
            gradientColors: ["#8b5cf6", "#6366f1"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 60,
            benefits: ["All-around fitness", "Power development", "Sport carryover"],
            preview: "Strength, power, and conditioning",
            tags: ["athletic", "sports", "power", "conditioning"],
            popularityScore: 81,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "int_minimalist_4w",
            name: "Minimalist Muscle",
            subtitle: "Maximum results, minimum time",
            description: "An efficient program for busy people. Only 3 exercises per workout, but highly effective.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .gainStrength],
            frequency: .four,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells"],
            icon: "minus.circle.fill",
            gradientColors: ["#64748b", "#475569"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 40,
            benefits: ["Time efficient", "Compound focus", "High intensity"],
            preview: "45-minute power workouts",
            tags: ["minimalist", "efficient", "busy", "compound"],
            popularityScore: 77,
            isFeatured: false,
            isNew: false
        ))
        
        // ========================================
        // ADVANCED PROGRAMS (25 programs)
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "adv_ppl_16w",
            name: "Elite PPL",
            subtitle: "16 weeks of advanced training",
            description: "An advanced periodized PPL with DUP, intensity techniques, and planned deloads.",
            duration: .fourMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle, .bodybuilding],
            frequency: .six,
            split: .pushPullLegs,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "crown.fill",
            gradientColors: ["#f59e0b", "#d97706"],
            workoutsPerWeek: 6,
            avgWorkoutMinutes: 80,
            benefits: ["Periodized", "Advanced techniques", "Competition prep"],
            preview: "Elite level muscle building",
            tags: ["advanced", "ppl", "periodization", "elite"],
            popularityScore: 93,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_powerlifting_12w",
            name: "Powerlifting Peak",
            subtitle: "Peak for competition",
            description: "A 12-week peaking program for powerlifting. Build to PRs in squat, bench, and deadlift.",
            duration: .threeMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.gainStrength, .powerlifting],
            frequency: .four,
            split: .custom,
            equipment: ["Barbell", "Power Rack", "Bench"],
            icon: "trophy.fill",
            gradientColors: ["#dc2626", "#991b1b"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 90,
            benefits: ["Peak strength", "Competition ready", "PR focused"],
            preview: "Squat, Bench, Deadlift focus",
            tags: ["powerlifting", "competition", "strength", "peaking"],
            popularityScore: 90,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_volume_12w",
            name: "German Volume Training",
            subtitle: "10x10 for massive gains",
            description: "The classic GVT program: 10 sets of 10 reps. Extreme volume for extreme results.",
            duration: .threeMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle, .bodybuilding],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "chart.bar.fill",
            gradientColors: ["#1e40af", "#1d4ed8"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 75,
            benefits: ["Extreme volume", "Massive pumps", "Size gains"],
            preview: "10 sets x 10 reps = growth",
            tags: ["gvt", "volume", "hypertrophy", "10x10"],
            popularityScore: 85,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_phat_12w",
            name: "PHAT Advanced",
            subtitle: "Power Hypertrophy Adaptive",
            description: "Layne Norton's PHAT for advanced lifters. Heavy power days followed by high-volume hypertrophy days.",
            duration: .threeMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle, .gainStrength, .powerlifting],
            frequency: .five,
            split: .phat,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "bolt.circle.fill",
            gradientColors: ["#7c3aed", "#5b21b6"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 85,
            benefits: ["Strength + size", "Scientific approach", "Advanced periodization"],
            preview: "2 power + 3 hypertrophy days",
            tags: ["phat", "powerbuilding", "advanced", "layne norton"],
            popularityScore: 88,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_contest_16w",
            name: "Contest Prep",
            subtitle: "Competition ready in 16 weeks",
            description: "A complete bodybuilding contest preparation program with phases for building, cutting, and peaking.",
            duration: .fourMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.bodybuilding, .loseWeight, .toneUp],
            frequency: .six,
            split: .pushPullLegs,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "medal.fill",
            gradientColors: ["#f59e0b", "#b45309"],
            workoutsPerWeek: 6,
            avgWorkoutMinutes: 90,
            benefits: ["Stage ready", "Peak condition", "Complete prep"],
            preview: "From bulk to stage condition",
            tags: ["contest", "competition", "bodybuilding", "prep"],
            popularityScore: 82,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_strength_16w",
            name: "Strength Maximizer",
            subtitle: "Break all your PRs",
            description: "A 16-week periodized strength program using block periodization and autoregulation.",
            duration: .fourMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.gainStrength, .powerlifting],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Power Rack", "Bench", "Dumbbells"],
            icon: "arrow.up.circle.fill",
            gradientColors: ["#ef4444", "#b91c1c"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 80,
            benefits: ["Massive PRs", "Block periodization", "Autoregulation"],
            preview: "4 months to your strongest",
            tags: ["strength", "powerlifting", "periodization", "max"],
            popularityScore: 86,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_specialization_8w",
            name: "Arm Specialization",
            subtitle: "Bring up your arms",
            description: "An 8-week program focused on arm development while maintaining other muscle groups.",
            duration: .twoMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle, .bodybuilding],
            frequency: .five,
            split: .custom,
            equipment: ["Dumbbells", "Cables", "EZ Bar", "Machines"],
            icon: "figure.arms.open",
            gradientColors: ["#ec4899", "#be185d"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 65,
            benefits: ["Arm focused", "Specialization", "Bring up weak points"],
            preview: "3 arm days per week",
            tags: ["arms", "biceps", "triceps", "specialization"],
            popularityScore: 76,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_legs_8w",
            name: "Leg Destroyer",
            subtitle: "Build massive wheels",
            description: "An intense leg specialization program hitting legs 3x per week. Not for the faint of heart.",
            duration: .twoMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle, .gainStrength],
            frequency: .five,
            split: .custom,
            equipment: ["Barbell", "Leg Press", "Hack Squat", "Dumbbells"],
            icon: "figure.walk",
            gradientColors: ["#0891b2", "#0e7490"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 70,
            benefits: ["Leg focus", "Quad and ham development", "Strength gains"],
            preview: "3 brutal leg days per week",
            tags: ["legs", "quads", "hamstrings", "specialization"],
            popularityScore: 74,
            isFeatured: false,
            isNew: false
        ))
        
        // ========================================
        // HOME / MINIMAL EQUIPMENT PROGRAMS (10 more)
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "home_dumbbell_12w",
            name: "Dumbbell Only Domination",
            subtitle: "Transform with dumbbells",
            description: "A complete 12-week program using only dumbbells. Build a great physique without a gym membership.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .home,
            goals: [.buildMuscle, .toneUp],
            frequency: .five,
            split: .pushPullLegs,
            equipment: ["Dumbbells"],
            icon: "dumbbell.fill",
            gradientColors: ["#8b5cf6", "#7c3aed"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 45,
            benefits: ["Home convenience", "Full development", "Minimal equipment"],
            preview: "Complete dumbbell transformation",
            tags: ["dumbbells", "home", "minimal", "transform"],
            popularityScore: 91,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "home_bands_4w",
            name: "Band Warrior",
            subtitle: "Resistance band training",
            description: "Build muscle and strength using only resistance bands. Perfect for travel or home use.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .minimal,
            goals: [.toneUp, .generalFitness],
            frequency: .four,
            split: .fullBody,
            equipment: ["Resistance Bands"],
            icon: "circle.dashed",
            gradientColors: ["#ec4899", "#f472b6"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 35,
            benefits: ["Portable", "Joint friendly", "Constant tension"],
            preview: "Complete band workouts",
            tags: ["bands", "resistance bands", "travel", "portable"],
            popularityScore: 75,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "home_kettlebell_8w",
            name: "Kettlebell Crusher",
            subtitle: "Total body kettlebell training",
            description: "A complete program using kettlebells. Build strength, power, and conditioning.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .home,
            goals: [.gainStrength, .athletic, .loseWeight],
            frequency: .four,
            split: .fullBody,
            equipment: ["Kettlebells"],
            icon: "circle.fill",
            gradientColors: ["#f97316", "#ea580c"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 40,
            benefits: ["Full body", "Cardio + strength", "Functional fitness"],
            preview: "Kettlebell swings, cleans, snatches",
            tags: ["kettlebell", "functional", "conditioning", "power"],
            popularityScore: 80,
            isFeatured: false,
            isNew: false
        ))
        
        // ========================================
        // SPECIALTY PROGRAMS
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "spec_deload_1w",
            name: "Strategic Deload",
            subtitle: "Recover and come back stronger",
            description: "A planned deload week to help your body recover from intense training. Use every 4-6 weeks.",
            duration: .oneWeek,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.flexibility, .generalFitness],
            frequency: .three,
            split: .fullBody,
            equipment: ["Bodyweight", "Dumbbells"],
            icon: "bed.double.fill",
            gradientColors: ["#6366f1", "#4f46e5"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 30,
            benefits: ["Recovery", "Reduced fatigue", "Prevent overtraining"],
            preview: "Light training, maximum recovery",
            tags: ["deload", "recovery", "rest", "regeneration"],
            popularityScore: 68,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "spec_pump_4w",
            name: "Pump Chaser",
            subtitle: "Maximum muscle pump",
            description: "High rep, high volume training designed to maximize the pump and build muscle endurance.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .improveEndurance],
            frequency: .five,
            split: .bro,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "bolt.heart.fill",
            gradientColors: ["#f43f5e", "#e11d48"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 55,
            benefits: ["Massive pumps", "Muscle endurance", "Definition"],
            preview: "High reps, skin-splitting pumps",
            tags: ["pump", "high rep", "endurance", "volume"],
            popularityScore: 73,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "spec_morning_4w",
            name: "Morning Warrior",
            subtitle: "Early AM training",
            description: "Quick, effective workouts designed for early morning training before work.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .hybrid,
            goals: [.generalFitness, .toneUp],
            frequency: .five,
            split: .fullBody,
            equipment: ["Dumbbells", "Bodyweight"],
            icon: "sunrise.fill",
            gradientColors: ["#fbbf24", "#f59e0b"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 35,
            benefits: ["Time efficient", "Boost metabolism", "Energize your day"],
            preview: "35-minute morning workouts",
            tags: ["morning", "quick", "efficient", "early"],
            popularityScore: 78,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "spec_lunch_4w",
            name: "Lunch Break Lifter",
            subtitle: "Fit in your workout at lunch",
            description: "30-minute workouts designed to fit in your lunch break. In, out, and back to work.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.generalFitness, .buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells"],
            icon: "fork.knife",
            gradientColors: ["#22c55e", "#16a34a"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 30,
            benefits: ["Quick workouts", "Compound focus", "Time efficient"],
            preview: "30-minute express workouts",
            tags: ["lunch", "quick", "30 minute", "express"],
            popularityScore: 71,
            isFeatured: false,
            isNew: false
        ))
        
        // Add more programs to reach ~100
        // ... (Adding remaining programs with diverse characteristics)
        
        // Women-focused programs
        programs.append(ExtendedProgram(
            id: "women_glutes_8w",
            name: "Glute Builder",
            subtitle: "Build your best glutes",
            description: "An 8-week program focused on glute development with hip thrusts, squats, and more.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .toneUp],
            frequency: .four,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Hip Thrust Machine", "Cables"],
            icon: "figure.walk.motion",
            gradientColors: ["#f472b6", "#ec4899"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["Glute focused", "Hip development", "Leg shaping"],
            preview: "4 glute-focused days per week",
            tags: ["glutes", "booty", "legs", "shaping"],
            popularityScore: 89,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "women_tone_12w",
            name: "12-Week Tone Up",
            subtitle: "Sculpt and define",
            description: "A complete program for toning and defining your entire body over 12 weeks.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.toneUp, .loseWeight],
            frequency: .five,
            split: .upperLower,
            equipment: ["Dumbbells", "Cables", "Machines", "Bodyweight"],
            icon: "sparkles",
            gradientColors: ["#a855f7", "#9333ea"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 50,
            benefits: ["Full body toning", "Fat loss", "Muscle definition"],
            preview: "12 weeks to your best shape",
            tags: ["toning", "definition", "sculpt", "lean"],
            popularityScore: 87,
            isFeatured: false,
            isNew: false
        ))
        
        // Sport-specific programs
        programs.append(ExtendedProgram(
            id: "sport_basketball_8w",
            name: "Basketball Performance",
            subtitle: "Jump higher, move faster",
            description: "Improve your vertical jump, agility, and court endurance for basketball.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.athletic, .improveEndurance],
            frequency: .four,
            split: .custom,
            equipment: ["Barbell", "Plyometric Boxes", "Dumbbells"],
            icon: "basketball.fill",
            gradientColors: ["#ea580c", "#c2410c"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 55,
            benefits: ["Vertical jump", "Agility", "Game endurance"],
            preview: "Jump, sprint, dominate",
            tags: ["basketball", "jumping", "agility", "sports"],
            popularityScore: 72,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "sport_football_12w",
            name: "Football Strength",
            subtitle: "Build game-winning power",
            description: "A complete off-season program for football players focused on strength, power, and size.",
            duration: .threeMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.gainStrength, .athletic, .buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells", "Sleds", "Chains"],
            icon: "football.fill",
            gradientColors: ["#854d0e", "#713f12"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 70,
            benefits: ["Raw power", "Game strength", "Size gains"],
            preview: "12-week off-season program",
            tags: ["football", "power", "strength", "sports"],
            popularityScore: 69,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "sport_running_8w",
            name: "Strength for Runners",
            subtitle: "Run faster, prevent injury",
            description: "A supplementary strength program for runners to improve performance and prevent injuries.",
            duration: .twoMonths,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.athletic, .improveEndurance, .flexibility],
            frequency: .two,
            split: .fullBody,
            equipment: ["Dumbbells", "Resistance Bands", "Bodyweight"],
            icon: "figure.run",
            gradientColors: ["#059669", "#047857"],
            workoutsPerWeek: 2,
            avgWorkoutMinutes: 35,
            benefits: ["Running economy", "Injury prevention", "Leg strength"],
            preview: "2 days of runner-specific strength",
            tags: ["running", "endurance", "cardio", "supplementary"],
            popularityScore: 65,
            isFeatured: false,
            isNew: false
        ))
        
        // Age-specific programs
        programs.append(ExtendedProgram(
            id: "age_40plus_12w",
            name: "Fit Over 40",
            subtitle: "Smart training for longevity",
            description: "A program designed for lifters over 40 with emphasis on joint health and sustainable progress.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.generalFitness, .flexibility, .buildMuscle],
            frequency: .four,
            split: .fullBody,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "heart.circle.fill",
            gradientColors: ["#0d9488", "#0f766e"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["Joint friendly", "Sustainable", "Longevity focused"],
            preview: "Smart training for the long run",
            tags: ["40+", "masters", "longevity", "sustainable"],
            popularityScore: 76,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "age_teen_8w",
            name: "Teen Athlete Foundation",
            subtitle: "Build your athletic base",
            description: "A safe, effective program for teenage athletes to build strength and proper movement patterns.",
            duration: .twoMonths,
            difficulty: .beginner,
            location: .gym,
            goals: [.athletic, .gainStrength, .generalFitness],
            frequency: .three,
            split: .fullBody,
            equipment: ["Bodyweight", "Dumbbells", "Medicine Ball"],
            icon: "person.fill",
            gradientColors: ["#3b82f6", "#2563eb"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 45,
            benefits: ["Proper form", "Athletic development", "Safe progression"],
            preview: "Build your foundation",
            tags: ["teen", "youth", "beginner", "athletic"],
            popularityScore: 70,
            isFeatured: false,
            isNew: false
        ))
        
        // More variety programs
        programs.append(ExtendedProgram(
            id: "variety_circuit_4w",
            name: "Circuit Training Blitz",
            subtitle: "High-intensity circuit training",
            description: "Fast-paced circuit training for maximum calorie burn and conditioning.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.loseWeight, .improveEndurance],
            frequency: .four,
            split: .fullBody,
            equipment: ["Dumbbells", "Kettlebells", "Bodyweight"],
            icon: "arrow.triangle.2.circlepath.circle.fill",
            gradientColors: ["#ef4444", "#f97316"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 40,
            benefits: ["High calorie burn", "Cardiovascular", "Time efficient"],
            preview: "Non-stop circuit action",
            tags: ["circuit", "cardio", "hiit", "conditioning"],
            popularityScore: 83,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "variety_supersets_6w",
            name: "Superset Shred",
            subtitle: "Non-stop muscle action",
            description: "A program built entirely around supersets for maximum efficiency and pump.",
            duration: .sixWeeks,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .loseWeight],
            frequency: .four,
            split: .upperLower,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "bolt.fill",
            gradientColors: ["#8b5cf6", "#6366f1"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 45,
            benefits: ["Time efficient", "Great pumps", "Fat burning"],
            preview: "Supersets every workout",
            tags: ["supersets", "intensity", "pump", "efficient"],
            popularityScore: 77,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "variety_dropsets_4w",
            name: "Drop Set Destroyer",
            subtitle: "Take every set to failure",
            description: "An intense program using drop sets on every exercise for maximum muscle fatigue.",
            duration: .oneMonth,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle, .bodybuilding],
            frequency: .four,
            split: .bro,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "arrow.down.circle.fill",
            gradientColors: ["#dc2626", "#b91c1c"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 55,
            benefits: ["Maximum fatigue", "Muscle breakdown", "Intensity"],
            preview: "Drop sets on everything",
            tags: ["drop sets", "intensity", "failure", "advanced"],
            popularityScore: 71,
            isFeatured: false,
            isNew: false
        ))
        
        // ========================================
        // MORE BEGINNER PROGRAMS
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "beg_machine_4w",
            name: "Machine Mastery",
            subtitle: "Learn on machines first",
            description: "A beginner-friendly program using only machines. Safer learning curve with guided movements.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .gym,
            goals: [.generalFitness, .buildMuscle],
            frequency: .three,
            split: .fullBody,
            equipment: ["Machines"],
            icon: "gearshape.fill",
            gradientColors: ["#0891b2", "#06b6d4"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 40,
            benefits: ["Guided movements", "Lower injury risk", "Learn muscle activation"],
            preview: "Machine-only workouts for beginners",
            tags: ["machines", "beginner", "safe", "guided"],
            popularityScore: 79,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_senior_8w",
            name: "Active Aging",
            subtitle: "Fitness for 50+",
            description: "A gentle program designed for older adults focusing on functional fitness and joint health.",
            duration: .twoMonths,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.generalFitness, .flexibility],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Resistance Bands", "Bodyweight"],
            icon: "heart.text.square.fill",
            gradientColors: ["#8b5cf6", "#a855f7"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 35,
            benefits: ["Joint friendly", "Functional strength", "Balance improvement"],
            preview: "Gentle, effective workouts",
            tags: ["senior", "50+", "gentle", "functional"],
            popularityScore: 74,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_posture_4w",
            name: "Posture Perfect",
            subtitle: "Fix your posture",
            description: "Correct muscle imbalances and improve posture with targeted exercises.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .minimal,
            goals: [.flexibility, .generalFitness],
            frequency: .four,
            split: .fullBody,
            equipment: ["Resistance Bands", "Bodyweight"],
            icon: "figure.stand",
            gradientColors: ["#14b8a6", "#2dd4bf"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 25,
            benefits: ["Better posture", "Reduced pain", "Core activation"],
            preview: "Daily posture correction routine",
            tags: ["posture", "desk worker", "back pain", "correction"],
            popularityScore: 76,
            isFeatured: false,
            isNew: false
        ))
        
        // ========================================
        // MORE INTERMEDIATE PROGRAMS
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "int_density_6w",
            name: "Density Training",
            subtitle: "More work in less time",
            description: "Progressive density training: do more reps in the same time each week.",
            duration: .sixWeeks,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .improveEndurance],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "square.stack.3d.up.fill",
            gradientColors: ["#6366f1", "#818cf8"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 45,
            benefits: ["Time efficient", "Progressive density", "Metabolic conditioning"],
            preview: "Beat your rep count each week",
            tags: ["density", "EDT", "timed sets", "progressive"],
            popularityScore: 73,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_powerbuilding_12w",
            name: "Powerbuilding Pro",
            subtitle: "Strength meets aesthetics",
            description: "The ultimate program combining powerlifting strength with bodybuilding aesthetics.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .buildMuscle, .powerlifting],
            frequency: .five,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "trophy.fill",
            gradientColors: ["#dc2626", "#f59e0b"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 70,
            benefits: ["Raw strength", "Aesthetic physique", "Best of both worlds"],
            preview: "Lift heavy, look great",
            tags: ["powerbuilding", "strength", "aesthetics", "hybrid"],
            popularityScore: 89,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_rest_pause_4w",
            name: "Rest-Pause Intensity",
            subtitle: "Maximum tension training",
            description: "Use rest-pause techniques to maximize muscle tension and growth stimulus.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .four,
            split: .bro,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "pause.circle.fill",
            gradientColors: ["#f43f5e", "#fb7185"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["High intensity", "Time under tension", "Growth stimulus"],
            preview: "Rest-pause every exercise",
            tags: ["rest pause", "intensity", "advanced technique", "hypertrophy"],
            popularityScore: 70,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_conjugate_12w",
            name: "Conjugate Method",
            subtitle: "Westside-inspired training",
            description: "Rotate max effort and dynamic effort days for continuous strength gains.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .powerlifting],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Chains", "Bands", "Power Rack"],
            icon: "arrow.triangle.swap",
            gradientColors: ["#1f2937", "#374151"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 75,
            benefits: ["Continuous adaptation", "Varied stimulus", "Break plateaus"],
            preview: "Max effort + dynamic effort",
            tags: ["conjugate", "westside", "powerlifting", "rotation"],
            popularityScore: 75,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_531_12w",
            name: "5/3/1 Forever",
            subtitle: "Jim Wendler's proven system",
            description: "The classic 5/3/1 program with accessory work for steady, sustainable gains.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .four,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Power Rack"],
            icon: "number.circle.fill",
            gradientColors: ["#0369a1", "#0284c7"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 60,
            benefits: ["Proven results", "Sustainable progression", "Long-term gains"],
            preview: "5/3/1 wave loading",
            tags: ["531", "wendler", "strength", "proven"],
            popularityScore: 92,
            isFeatured: true,
            isNew: false
        ))
        
        // ========================================
        // MORE ADVANCED PROGRAMS
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "adv_doggcrapp_12w",
            name: "DC Training",
            subtitle: "High intensity, low frequency",
            description: "Doggcrapp-inspired training: extreme stretching, rest-pause, and progressive overload.",
            duration: .threeMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle, .bodybuilding],
            frequency: .three,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Cables", "Machines"],
            icon: "bolt.circle.fill",
            gradientColors: ["#7c3aed", "#a855f7"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 70,
            benefits: ["Extreme intensity", "Maximum recovery", "Serious gains"],
            preview: "3 brutal sessions per week",
            tags: ["doggcrapp", "DC", "intense", "rest pause"],
            popularityScore: 78,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_smolov_13w",
            name: "Smolov Squat",
            subtitle: "Russian squat protocol",
            description: "The notorious Smolov squat program for serious squat gains. Not for the faint of heart.",
            duration: .threeMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.gainStrength, .powerlifting],
            frequency: .four,
            split: .custom,
            equipment: ["Barbell", "Power Rack"],
            icon: "flame.circle.fill",
            gradientColors: ["#dc2626", "#7f1d1d"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 60,
            benefits: ["Massive squat gains", "Mental toughness", "Russian methodology"],
            preview: "Squat 4x/week brutality",
            tags: ["smolov", "squat", "russian", "brutal"],
            popularityScore: 72,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_widowmaker_8w",
            name: "Widowmaker Protocol",
            subtitle: "20-rep squat hell",
            description: "The classic 20-rep squat program that builds legs and mental fortitude.",
            duration: .twoMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle, .gainStrength],
            frequency: .three,
            split: .fullBody,
            equipment: ["Barbell", "Power Rack"],
            icon: "exclamationmark.triangle.fill",
            gradientColors: ["#b91c1c", "#991b1b"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 45,
            benefits: ["Massive leg growth", "Mental toughness", "Full body stimulus"],
            preview: "20-rep breathing squats",
            tags: ["widowmaker", "20 rep", "squats", "brutal"],
            popularityScore: 69,
            isFeatured: false,
            isNew: false
        ))
        
        // ========================================
        // GOAL-SPECIFIC PROGRAMS
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "goal_recomp_12w",
            name: "Body Recomposition",
            subtitle: "Lose fat, gain muscle",
            description: "The holy grail: lose fat while building muscle simultaneously with strategic training and nutrition timing.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .loseWeight, .toneUp],
            frequency: .five,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "arrow.left.arrow.right.circle.fill",
            gradientColors: ["#059669", "#10b981"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 55,
            benefits: ["Fat loss", "Muscle gain", "Body transformation"],
            preview: "Transform your physique",
            tags: ["recomposition", "recomp", "fat loss", "muscle gain"],
            popularityScore: 94,
            isFeatured: true,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "goal_vacation_4w",
            name: "Vacation Ready",
            subtitle: "Look great in 4 weeks",
            description: "A focused 4-week program to look your best for vacation or a special event.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.loseWeight, .toneUp],
            frequency: .five,
            split: .pushPullLegs,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "airplane",
            gradientColors: ["#0ea5e9", "#38bdf8"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 50,
            benefits: ["Quick results", "Beach ready", "Muscle definition"],
            preview: "4 weeks to beach body",
            tags: ["vacation", "beach body", "quick", "definition"],
            popularityScore: 85,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "goal_wedding_12w",
            name: "Wedding Ready",
            subtitle: "Look perfect for your big day",
            description: "A 12-week program designed to help you look and feel amazing for your wedding.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .hybrid,
            goals: [.toneUp, .loseWeight, .generalFitness],
            frequency: .four,
            split: .fullBody,
            equipment: ["Dumbbells", "Resistance Bands", "Bodyweight"],
            icon: "heart.fill",
            gradientColors: ["#f472b6", "#f9a8d4"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 45,
            benefits: ["Gradual transformation", "Stress relief", "Confidence boost"],
            preview: "12 weeks to your best self",
            tags: ["wedding", "event", "special occasion", "transformation"],
            popularityScore: 77,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "goal_comeback_8w",
            name: "Comeback Program",
            subtitle: "Return after a break",
            description: "Getting back into fitness after time off? This program eases you back safely.",
            duration: .twoMonths,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.generalFitness, .buildMuscle],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Bodyweight"],
            icon: "arrow.uturn.up.circle.fill",
            gradientColors: ["#22c55e", "#4ade80"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 40,
            benefits: ["Safe return", "Rebuild base", "Prevent injury"],
            preview: "Ease back into training",
            tags: ["comeback", "return", "break", "restart"],
            popularityScore: 80,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "goal_maintenance_ongoing",
            name: "Maintenance Mode",
            subtitle: "Keep your gains",
            description: "A sustainable program to maintain your physique with minimal time investment.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.generalFitness, .buildMuscle],
            frequency: .two,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells"],
            icon: "checkmark.seal.fill",
            gradientColors: ["#6b7280", "#9ca3af"],
            workoutsPerWeek: 2,
            avgWorkoutMinutes: 45,
            benefits: ["Maintain gains", "Time efficient", "Sustainable"],
            preview: "2 workouts to keep your gains",
            tags: ["maintenance", "minimal", "sustainable", "busy"],
            popularityScore: 67,
            isFeatured: false,
            isNew: false
        ))
        
        // ========================================
        // MORE HOME/OUTDOOR PROGRAMS
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "home_garage_12w",
            name: "Garage Gym Hero",
            subtitle: "Complete home gym program",
            description: "A full program for those with a barbell, rack, and bench at home.",
            duration: .threeMonths,
            difficulty: .intermediate,
            location: .home,
            goals: [.gainStrength, .buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Power Rack", "Bench", "Dumbbells"],
            icon: "house.circle.fill",
            gradientColors: ["#f97316", "#fb923c"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 60,
            benefits: ["Full program at home", "Serious gains", "No gym needed"],
            preview: "Home gym powerlifting",
            tags: ["garage gym", "home gym", "barbell", "powerlifting"],
            popularityScore: 86,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "outdoor_park_8w",
            name: "Park Warrior",
            subtitle: "Outdoor calisthenics",
            description: "Use park equipment and your bodyweight for a complete outdoor program.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .outdoor,
            goals: [.buildMuscle, .athletic],
            frequency: .four,
            split: .pushPullLegs,
            equipment: ["Pull-Up Bar", "Parallel Bars", "Bodyweight"],
            icon: "leaf.fill",
            gradientColors: ["#16a34a", "#22c55e"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 45,
            benefits: ["Fresh air", "Free workouts", "Functional strength"],
            preview: "Train at the park",
            tags: ["outdoor", "park", "calisthenics", "free"],
            popularityScore: 74,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "home_hiit_4w",
            name: "HIIT at Home",
            subtitle: "High intensity cardio",
            description: "Intense HIIT workouts you can do in your living room with no equipment.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .minimal,
            goals: [.loseWeight, .improveEndurance],
            frequency: .four,
            split: .fullBody,
            equipment: ["Bodyweight"],
            icon: "heart.circle.fill",
            gradientColors: ["#ef4444", "#f87171"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 25,
            benefits: ["Maximum calorie burn", "No equipment", "Short workouts"],
            preview: "25-minute HIIT sessions",
            tags: ["hiit", "cardio", "home", "fat burning"],
            popularityScore: 88,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "home_yoga_strength_6w",
            name: "Yoga Strength Fusion",
            subtitle: "Flexibility meets strength",
            description: "Combine yoga flows with strength training for complete mind-body fitness.",
            duration: .sixWeeks,
            difficulty: .beginner,
            location: .minimal,
            goals: [.flexibility, .toneUp, .generalFitness],
            frequency: .five,
            split: .fullBody,
            equipment: ["Bodyweight", "Dumbbells"],
            icon: "figure.mind.and.body",
            gradientColors: ["#a855f7", "#c084fc"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 40,
            benefits: ["Flexibility", "Strength", "Mental clarity"],
            preview: "Yoga meets weights",
            tags: ["yoga", "flexibility", "strength", "mind body"],
            popularityScore: 79,
            isFeatured: false,
            isNew: true
        ))
        
        // ========================================
        // FINAL SPECIALTY PROGRAMS
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "spec_myo_6w",
            name: "Myo-Rep Mastery",
            subtitle: "Activation set intensity",
            description: "Use myo-reps to maximize effective reps and minimize junk volume.",
            duration: .sixWeeks,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "waveform.circle.fill",
            gradientColors: ["#0891b2", "#22d3ee"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 40,
            benefits: ["Time efficient", "Maximum growth stimulus", "Less junk volume"],
            preview: "Activation sets + mini sets",
            tags: ["myo reps", "intensity", "efficient", "hypertrophy"],
            popularityScore: 72,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "spec_amrap_4w",
            name: "AMRAP Challenge",
            subtitle: "As many reps as possible",
            description: "Every workout ends with an AMRAP set. Beat your numbers each week.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .improveEndurance],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells"],
            icon: "arrow.up.circle.fill",
            gradientColors: ["#ea580c", "#f97316"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["Progressive challenge", "Mental toughness", "Track progress"],
            preview: "Push to failure every workout",
            tags: ["amrap", "challenge", "progressive", "failure"],
            popularityScore: 73,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "spec_1000rep_2w",
            name: "1000 Rep Challenge",
            subtitle: "The ultimate test",
            description: "Can you complete 1000 reps per workout? A 2-week mental and physical challenge.",
            duration: .twoWeeks,
            difficulty: .advanced,
            location: .gym,
            goals: [.improveEndurance, .buildMuscle],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Bodyweight", "Cables"],
            icon: "flame",
            gradientColors: ["#dc2626", "#ef4444"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 90,
            benefits: ["Mental challenge", "Endurance test", "Unique experience"],
            preview: "1000 reps per session",
            tags: ["challenge", "1000", "endurance", "mental"],
            popularityScore: 65,
            isFeatured: false,
            isNew: true
        ))
        
        // ========================================
        // ADDITIONAL PROGRAMS TO REACH 100
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "int_chest_focus_4w",
            name: "Chest Specialization",
            subtitle: "Build a bigger chest",
            description: "A 4-week program to bring up your chest with increased frequency and volume.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .five,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "figure.strengthtraining.traditional",
            gradientColors: ["#dc2626", "#f87171"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 55,
            benefits: ["Chest focus", "Increased frequency", "Bring up weak point"],
            preview: "3 chest days per week",
            tags: ["chest", "specialization", "pecs", "upper body"],
            popularityScore: 77,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_back_focus_4w",
            name: "Back Blaster",
            subtitle: "Build a wider back",
            description: "Focus on lat width and back thickness with this specialized 4-week program.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .five,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Cables", "Pull-Up Bar"],
            icon: "figure.strengthtraining.functional",
            gradientColors: ["#4f46e5", "#818cf8"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 55,
            benefits: ["Back width", "Lat development", "V-taper"],
            preview: "3 back days per week",
            tags: ["back", "lats", "width", "v-taper"],
            popularityScore: 76,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_shoulders_4w",
            name: "Boulder Shoulders",
            subtitle: "Build capped delts",
            description: "Target all three delt heads for 3D shoulder development.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .five,
            split: .custom,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "arrow.up.left.and.arrow.down.right",
            gradientColors: ["#f59e0b", "#fbbf24"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 50,
            benefits: ["Capped delts", "3D shoulders", "Side delt focus"],
            preview: "High frequency shoulder training",
            tags: ["shoulders", "delts", "capped", "boulder"],
            popularityScore: 75,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_cardio_weights_6w",
            name: "Cardio + Weights Combo",
            subtitle: "Best of both worlds",
            description: "Combine cardio and weight training for balanced fitness improvement.",
            duration: .sixWeeks,
            difficulty: .beginner,
            location: .gym,
            goals: [.loseWeight, .improveEndurance, .toneUp],
            frequency: .four,
            split: .fullBody,
            equipment: ["Dumbbells", "Treadmill", "Bodyweight"],
            icon: "heart.circle.fill",
            gradientColors: ["#ec4899", "#f472b6"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["Cardiovascular health", "Fat loss", "Muscle tone"],
            preview: "2 cardio + 2 weight days",
            tags: ["cardio", "weights", "combo", "balanced"],
            popularityScore: 81,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_metabolic_6w",
            name: "Metabolic Conditioning",
            subtitle: "Torch fat, build muscle",
            description: "High-intensity metabolic training to maximize calorie burn and muscle retention.",
            duration: .sixWeeks,
            difficulty: .advanced,
            location: .gym,
            goals: [.loseWeight, .improveEndurance],
            frequency: .five,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells", "Kettlebells"],
            icon: "flame.circle.fill",
            gradientColors: ["#ef4444", "#f97316"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 45,
            benefits: ["Extreme fat burn", "Metabolic boost", "EPOC effect"],
            preview: "High intensity circuits",
            tags: ["metabolic", "conditioning", "hiit", "fat burn"],
            popularityScore: 82,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_functional_8w",
            name: "Functional Fitness",
            subtitle: "Train for real life",
            description: "Build practical strength that transfers to everyday activities and sports.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.athletic, .gainStrength, .generalFitness],
            frequency: .four,
            split: .fullBody,
            equipment: ["Kettlebells", "Dumbbells", "Medicine Ball", "Bodyweight"],
            icon: "figure.mixed.cardio",
            gradientColors: ["#0891b2", "#22d3ee"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["Real-world strength", "Movement quality", "Athletic carry-over"],
            preview: "Functional movement patterns",
            tags: ["functional", "athletic", "movement", "practical"],
            popularityScore: 79,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_compound_4w",
            name: "Compound Essentials",
            subtitle: "Master the big lifts",
            description: "Focus exclusively on compound movements for maximum efficiency.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .three,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells"],
            icon: "square.stack.3d.down.dottedline",
            gradientColors: ["#4338ca", "#6366f1"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 45,
            benefits: ["Movement mastery", "Full body stimulus", "Efficient training"],
            preview: "Squat, bench, deadlift, row, press",
            tags: ["compound", "basics", "efficiency", "beginner"],
            popularityScore: 84,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_time_under_tension_6w",
            name: "Time Under Tension",
            subtitle: "Slow and controlled",
            description: "Focus on tempo training to maximize muscle fiber recruitment.",
            duration: .sixWeeks,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "clock.fill",
            gradientColors: ["#7c3aed", "#a855f7"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 55,
            benefits: ["Muscle control", "Mind-muscle connection", "Growth stimulus"],
            preview: "4-0-4-0 tempo training",
            tags: ["tempo", "TUT", "slow", "controlled"],
            popularityScore: 71,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_blood_flow_4w",
            name: "Blood Flow Restriction",
            subtitle: "BFR training protocol",
            description: "Use blood flow restriction for muscle growth with lighter weights.",
            duration: .oneMonth,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Dumbbells", "BFR Bands"],
            icon: "drop.circle.fill",
            gradientColors: ["#be123c", "#e11d48"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 45,
            benefits: ["Hypertrophy with light weight", "Joint friendly", "Metabolic stress"],
            preview: "BFR every session",
            tags: ["BFR", "blood flow", "occlusion", "advanced"],
            popularityScore: 68,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "int_cluster_sets_4w",
            name: "Cluster Set Protocol",
            subtitle: "Intra-set rest for power",
            description: "Use cluster sets to handle heavier weights with better form.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells"],
            icon: "rectangle.split.3x1.fill",
            gradientColors: ["#0f766e", "#14b8a6"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 60,
            benefits: ["Handle heavier weight", "Quality reps", "Strength gains"],
            preview: "Cluster sets on compounds",
            tags: ["cluster sets", "rest pause", "strength", "technique"],
            popularityScore: 69,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_habit_2w",
            name: "2-Week Habit Builder",
            subtitle: "Build the gym habit",
            description: "A short program focused on building consistent gym habits.",
            duration: .twoWeeks,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.generalFitness],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Bodyweight"],
            icon: "checkmark.circle.fill",
            gradientColors: ["#22c55e", "#4ade80"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 30,
            benefits: ["Build habit", "Consistency focus", "Low barrier"],
            preview: "Short, consistent workouts",
            tags: ["habit", "consistency", "beginner", "short"],
            popularityScore: 83,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_mind_muscle_4w",
            name: "Mind-Muscle Mastery",
            subtitle: "Feel every rep",
            description: "Focus on developing the mind-muscle connection for better gains.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .four,
            split: .bro,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "brain.head.profile",
            gradientColors: ["#6366f1", "#8b5cf6"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["Better connection", "Quality over quantity", "Muscle activation"],
            preview: "Focus on the squeeze",
            tags: ["mind muscle", "connection", "feel", "activation"],
            popularityScore: 74,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "sport_soccer_8w",
            name: "Soccer Performance",
            subtitle: "Improve on-field performance",
            description: "Build leg power, agility, and endurance for soccer players.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.athletic, .improveEndurance],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Resistance Bands", "Plyometric Boxes"],
            icon: "soccerball",
            gradientColors: ["#16a34a", "#22c55e"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 50,
            benefits: ["Leg power", "Agility", "Endurance"],
            preview: "Soccer-specific conditioning",
            tags: ["soccer", "football", "sports", "agility"],
            popularityScore: 66,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "sport_golf_8w",
            name: "Golf Fitness",
            subtitle: "Drive further, play better",
            description: "Improve rotational power and flexibility for golf.",
            duration: .twoMonths,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.athletic, .flexibility],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Resistance Bands", "Medicine Ball"],
            icon: "figure.golf",
            gradientColors: ["#15803d", "#22c55e"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 40,
            benefits: ["Rotational power", "Flexibility", "Core stability"],
            preview: "Golf-specific training",
            tags: ["golf", "rotation", "flexibility", "sports"],
            popularityScore: 62,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "sport_tennis_8w",
            name: "Tennis Strength",
            subtitle: "Serve harder, move faster",
            description: "Build explosive power and endurance for tennis players.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.athletic, .gainStrength],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Cables", "Medicine Ball"],
            icon: "figure.tennis",
            gradientColors: ["#ca8a04", "#eab308"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 45,
            benefits: ["Explosive power", "Shoulder stability", "Lateral movement"],
            preview: "Tennis-specific conditioning",
            tags: ["tennis", "racquet", "explosive", "sports"],
            popularityScore: 63,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "sport_swimming_8w",
            name: "Swim Strength",
            subtitle: "Stronger in the water",
            description: "Dryland training to improve swimming power and endurance.",
            duration: .twoMonths,
            difficulty: .intermediate,
            location: .gym,
            goals: [.athletic, .improveEndurance],
            frequency: .three,
            split: .fullBody,
            equipment: ["Resistance Bands", "Dumbbells", "Pull-Up Bar"],
            icon: "figure.pool.swim",
            gradientColors: ["#0284c7", "#0ea5e9"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 40,
            benefits: ["Pull strength", "Core stability", "Shoulder health"],
            preview: "Dryland training for swimmers",
            tags: ["swimming", "dryland", "endurance", "sports"],
            popularityScore: 61,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "sport_mma_12w",
            name: "MMA Conditioning",
            subtitle: "Fight-ready fitness",
            description: "Build the strength, power, and endurance needed for combat sports.",
            duration: .threeMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.athletic, .gainStrength, .improveEndurance],
            frequency: .five,
            split: .custom,
            equipment: ["Barbell", "Kettlebells", "Heavy Bag", "Bodyweight"],
            icon: "figure.martial.arts",
            gradientColors: ["#1f2937", "#374151"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 60,
            benefits: ["Fight conditioning", "Explosive power", "Mental toughness"],
            preview: "Strength + conditioning for fighters",
            tags: ["mma", "fighting", "combat", "conditioning"],
            popularityScore: 78,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_emom_4w",
            name: "EMOM Challenge",
            subtitle: "Every minute on the minute",
            description: "EMOM-style workouts for conditioning and work capacity.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.improveEndurance, .loseWeight],
            frequency: .four,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells", "Kettlebells"],
            icon: "timer",
            gradientColors: ["#ea580c", "#f97316"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 35,
            benefits: ["Work capacity", "Conditioning", "Time efficient"],
            preview: "EMOM every workout",
            tags: ["emom", "conditioning", "timed", "challenge"],
            popularityScore: 75,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_tabata_4w",
            name: "Tabata Terror",
            subtitle: "20 seconds of maximum effort",
            description: "True Tabata protocol: 20 seconds on, 10 seconds off, 8 rounds.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .hybrid,
            goals: [.loseWeight, .improveEndurance],
            frequency: .four,
            split: .fullBody,
            equipment: ["Bodyweight", "Dumbbells"],
            icon: "bolt.heart.fill",
            gradientColors: ["#dc2626", "#f87171"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 25,
            benefits: ["Maximum intensity", "Short workouts", "Fat burning"],
            preview: "True Tabata intervals",
            tags: ["tabata", "hiit", "intervals", "conditioning"],
            popularityScore: 80,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_minimal_travel_2w",
            name: "Travel Workout Pack",
            subtitle: "Stay fit on the road",
            description: "Workouts designed for hotel rooms with zero equipment.",
            duration: .twoWeeks,
            difficulty: .beginner,
            location: .minimal,
            goals: [.generalFitness],
            frequency: .four,
            split: .fullBody,
            equipment: ["Bodyweight"],
            icon: "airplane.departure",
            gradientColors: ["#3b82f6", "#60a5fa"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 20,
            benefits: ["Zero equipment", "Hotel room friendly", "Maintain fitness"],
            preview: "20-minute hotel workouts",
            tags: ["travel", "hotel", "no equipment", "portable"],
            popularityScore: 73,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_giant_sets_6w",
            name: "Giant Set Gauntlet",
            subtitle: "Non-stop muscle action",
            description: "Chain 4 exercises together with no rest for maximum pump and growth.",
            duration: .sixWeeks,
            difficulty: .advanced,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .four,
            split: .bro,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "square.fill.text.grid.1x2",
            gradientColors: ["#c026d3", "#e879f9"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 50,
            benefits: ["Maximum pump", "Time efficient", "Metabolic stress"],
            preview: "4-exercise giant sets",
            tags: ["giant sets", "supersets", "pump", "intensity"],
            popularityScore: 70,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_deskjob_4w",
            name: "Desk Worker Rescue",
            subtitle: "Undo sitting damage",
            description: "Combat the effects of desk work with targeted mobility and strength work.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.flexibility, .generalFitness],
            frequency: .four,
            split: .fullBody,
            equipment: ["Resistance Bands", "Dumbbells", "Bodyweight"],
            icon: "desktopcomputer",
            gradientColors: ["#0d9488", "#2dd4bf"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 35,
            benefits: ["Improve posture", "Reduce pain", "Increase mobility"],
            preview: "Undo desk damage",
            tags: ["desk job", "posture", "office worker", "mobility"],
            popularityScore: 78,
            isFeatured: false,
            isNew: true
        ))
        
        // ========================================
        // FINAL 10 PROGRAMS TO REACH 100
        // ========================================
        
        programs.append(ExtendedProgram(
            id: "int_reverse_pyramid_6w",
            name: "Reverse Pyramid Training",
            subtitle: "Heavy first, then lighter",
            description: "Start with your heaviest set when fresh, then drop weight and add reps.",
            duration: .sixWeeks,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .three,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells"],
            icon: "triangle.inset.filled",
            gradientColors: ["#7c2d12", "#ea580c"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 50,
            benefits: ["Maximum intensity first", "Efficient training", "Strength + size"],
            preview: "Heavy to light training",
            tags: ["RPT", "pyramid", "strength", "efficient"],
            popularityScore: 76,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_daily_undulating_12w",
            name: "Daily Undulating Periodization",
            subtitle: "Vary intensity daily",
            description: "Change rep ranges and intensity each training day for continuous adaptation.",
            duration: .threeMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .four,
            split: .upperLower,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "waveform.path",
            gradientColors: ["#1e3a8a", "#3b82f6"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 65,
            benefits: ["Avoid plateaus", "Continuous adaptation", "Varied stimulus"],
            preview: "Power, strength, hypertrophy rotation",
            tags: ["DUP", "periodization", "variety", "advanced"],
            popularityScore: 77,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_cable_only_4w",
            name: "Cable Machine Basics",
            subtitle: "Constant tension training",
            description: "Learn to use the cable machine for effective, joint-friendly training.",
            duration: .oneMonth,
            difficulty: .beginner,
            location: .gym,
            goals: [.buildMuscle, .toneUp],
            frequency: .three,
            split: .fullBody,
            equipment: ["Cables"],
            icon: "lines.measurement.horizontal",
            gradientColors: ["#059669", "#34d399"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 40,
            benefits: ["Constant tension", "Safe learning", "Joint friendly"],
            preview: "All cable workouts",
            tags: ["cables", "machines", "beginner", "tension"],
            popularityScore: 72,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_pre_exhaust_4w",
            name: "Pre-Exhaust Protocol",
            subtitle: "Isolate before compound",
            description: "Pre-fatigue muscles with isolation before compound movements.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle],
            frequency: .four,
            split: .bro,
            equipment: ["Dumbbells", "Cables", "Machines"],
            icon: "battery.50",
            gradientColors: ["#be185d", "#ec4899"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 55,
            benefits: ["Better mind-muscle connection", "Fatigue target muscle", "Unique stimulus"],
            preview: "Isolation then compound",
            tags: ["pre exhaust", "isolation", "compound", "technique"],
            popularityScore: 68,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_couple_8w",
            name: "Couples Fitness",
            subtitle: "Train together",
            description: "A program designed for couples to train together and motivate each other.",
            duration: .twoMonths,
            difficulty: .beginner,
            location: .hybrid,
            goals: [.generalFitness, .toneUp],
            frequency: .three,
            split: .fullBody,
            equipment: ["Dumbbells", "Bodyweight"],
            icon: "heart.text.square",
            gradientColors: ["#f43f5e", "#fb7185"],
            workoutsPerWeek: 3,
            avgWorkoutMinutes: 45,
            benefits: ["Partner motivation", "Shared experience", "Accountability"],
            preview: "Train as a team",
            tags: ["couples", "partner", "together", "motivation"],
            popularityScore: 71,
            isFeatured: false,
            isNew: true
        ))
        
        programs.append(ExtendedProgram(
            id: "int_high_frequency_6w",
            name: "High Frequency Full Body",
            subtitle: "Train more, recover faster",
            description: "Hit every muscle 5-6 times per week with lower volume per session.",
            duration: .sixWeeks,
            difficulty: .intermediate,
            location: .gym,
            goals: [.buildMuscle, .generalFitness],
            frequency: .six,
            split: .fullBody,
            equipment: ["Barbell", "Dumbbells"],
            icon: "bolt.fill",
            gradientColors: ["#0369a1", "#0ea5e9"],
            workoutsPerWeek: 6,
            avgWorkoutMinutes: 35,
            benefits: ["Maximum frequency", "Skill practice", "Natural lifter optimal"],
            preview: "Train everything, every day",
            tags: ["high frequency", "daily", "full body", "natural"],
            popularityScore: 74,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "adv_periodization_16w",
            name: "Block Periodization",
            subtitle: "Train in focused blocks",
            description: "Cycle through accumulation, transmutation, and realization phases.",
            duration: .fourMonths,
            difficulty: .advanced,
            location: .gym,
            goals: [.gainStrength, .powerlifting],
            frequency: .four,
            split: .custom,
            equipment: ["Barbell", "Power Rack", "Dumbbells"],
            icon: "square.stack.3d.up",
            gradientColors: ["#4c1d95", "#7c3aed"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 75,
            benefits: ["Systematic progression", "Peaking protocol", "Competition prep"],
            preview: "Accumulation → Transmutation → Realization",
            tags: ["block periodization", "peaking", "advanced", "powerlifting"],
            popularityScore: 73,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "beg_recovery_1w",
            name: "Active Recovery Week",
            subtitle: "Move and recover",
            description: "Light movement and stretching to promote recovery between intense training blocks.",
            duration: .oneWeek,
            difficulty: .beginner,
            location: .minimal,
            goals: [.flexibility, .generalFitness],
            frequency: .five,
            split: .fullBody,
            equipment: ["Bodyweight", "Foam Roller"],
            icon: "leaf.arrow.triangle.circlepath",
            gradientColors: ["#65a30d", "#84cc16"],
            workoutsPerWeek: 5,
            avgWorkoutMinutes: 25,
            benefits: ["Promote recovery", "Maintain mobility", "Reduce soreness"],
            preview: "Light movement daily",
            tags: ["recovery", "active recovery", "deload", "mobility"],
            popularityScore: 66,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_pull_focus_4w",
            name: "Pull Dominance",
            subtitle: "Master your pulls",
            description: "Focus on pulling strength: rows, pulldowns, deadlifts, and curls.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .four,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Cables", "Pull-Up Bar"],
            icon: "arrow.down.to.line",
            gradientColors: ["#0f766e", "#14b8a6"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 55,
            benefits: ["Back development", "Bicep growth", "Posture improvement"],
            preview: "Pull exercises every session",
            tags: ["pull", "back", "biceps", "rowing"],
            popularityScore: 72,
            isFeatured: false,
            isNew: false
        ))
        
        programs.append(ExtendedProgram(
            id: "int_push_focus_4w",
            name: "Push Power",
            subtitle: "Dominate the push",
            description: "Focus on pushing strength: bench, overhead press, dips, and triceps.",
            duration: .oneMonth,
            difficulty: .intermediate,
            location: .gym,
            goals: [.gainStrength, .buildMuscle],
            frequency: .four,
            split: .custom,
            equipment: ["Barbell", "Dumbbells", "Cables"],
            icon: "arrow.up.to.line",
            gradientColors: ["#b91c1c", "#ef4444"],
            workoutsPerWeek: 4,
            avgWorkoutMinutes: 55,
            benefits: ["Chest development", "Shoulder strength", "Tricep growth"],
            preview: "Push exercises every session",
            tags: ["push", "chest", "shoulders", "pressing"],
            popularityScore: 73,
            isFeatured: false,
            isNew: false
        ))
        
        // Return all programs sorted by popularity
        return programs.sorted { $0.popularityScore > $1.popularityScore }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}

