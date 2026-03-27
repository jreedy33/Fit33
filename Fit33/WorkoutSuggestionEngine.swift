import Foundation
import CoreData

/// Centralized engine that provides context-aware workout suggestions.
/// Used by the dashboard motivational message, daily quest descriptions,
/// and "Surprise Me" generation to avoid repetitive or counter-productive suggestions.
///
/// Key behaviors:
/// - Tracks which muscle groups were trained recently and their recovery state
/// - Respects active program schedules (generated, cloud, smart)
/// - Persists the last Surprise Me split to prevent back-to-back duplicates
/// - Provides a "what should the user do today?" recommendation
final class WorkoutSuggestionEngine: ObservableObject {
    static let shared = WorkoutSuggestionEngine()

    private let bgContext: NSManagedObjectContext = {
        let ctx = PersistenceController.shared.container.newBackgroundContext()
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }()

    // Cached recovery data — populated by async methods, read by sync callers (view bodies)
    private var cachedRecoveryStates: [MuscleRecoveryState]?
    private var cachedSplitFamilies: [SplitFamily]?
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 30

    // MARK: - Muscle Group Taxonomy

    enum MuscleCategory: String, CaseIterable {
        case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core, cardio
    }

    /// Maps free-text muscle names (from Core Data) to canonical categories.
    private static let muscleAliases: [String: MuscleCategory] = {
        var map: [String: MuscleCategory] = [:]
        let entries: [(MuscleCategory, [String])] = [
            (.chest,      ["chest", "pecs", "pectorals", "upper chest", "lower chest"]),
            (.back,       ["back", "lats", "traps", "rhomboids", "upper back", "lower back", "rear delts"]),
            (.shoulders,  ["shoulders", "delts", "front delts", "side delts", "deltoids"]),
            (.biceps,     ["biceps", "arms"]),
            (.triceps,    ["triceps"]),
            (.quads,      ["quads", "quadriceps", "legs"]),
            (.hamstrings, ["hamstrings", "hams"]),
            (.glutes,     ["glutes", "glute", "hip"]),
            (.calves,     ["calves", "calf"]),
            (.core,       ["core", "abs", "obliques", "abdominals"]),
            (.cardio,     ["cardio", "hiit", "plyometrics", "full body"])
        ]
        for (cat, aliases) in entries {
            for alias in aliases { map[alias] = cat }
        }
        return map
    }()

    /// Hours before a muscle group is considered recovered.
    /// Larger compound-movement groups need more rest.
    private static let recoveryHours: [MuscleCategory: Int] = [
        .chest: 48, .back: 48, .shoulders: 48,
        .quads: 72, .hamstrings: 72, .glutes: 72, .calves: 48,
        .biceps: 48, .triceps: 48, .core: 24, .cardio: 24
    ]

    /// Coarse "split family" used to prevent consecutive Surprise Me duplicates.
    enum SplitFamily: String, CaseIterable {
        case push, pull, legs, upperBody, fullBody, coreCardio
    }

    // MARK: - Persistence Keys

    private let lastSurpriseSplitKey = "wse_lastSurpriseSplitFamily"
    private let lastSurpriseDateKey  = "wse_lastSurpriseDate"

    // MARK: - Public Data

    struct MuscleRecoveryState {
        let category: MuscleCategory
        let lastTrainedDate: Date?
        let hoursElapsed: Int
        let recoveryHours: Int
        var isRecovered: Bool { lastTrainedDate == nil || hoursElapsed >= recoveryHours }
        var recoveryPercent: Double {
            guard let _ = lastTrainedDate else { return 1.0 }
            return min(1.0, Double(hoursElapsed) / Double(recoveryHours))
        }
    }

    struct TodaySuggestion {
        let primaryMessage: String
        let suggestedMuscles: [MuscleCategory]
        let splitFamily: SplitFamily
        let isFromProgram: Bool
        let programDayName: String?
    }

    // MARK: - Recovery Analysis

    /// Async version — fetches from Core Data without blocking the calling thread.
    func getMuscleRecoveryStatesAsync() async -> [MuscleRecoveryState] {
        let recentMusclesByDate = await getRecentMusclesWithDatesAsync(days: 5)
        let now = Date()

        let states = MuscleCategory.allCases.map { cat in
            let lastDate = recentMusclesByDate[cat]
            let hours = lastDate.map { Int(now.timeIntervalSince($0) / 3600) } ?? Int.max
            let recovery = Self.recoveryHours[cat] ?? 48
            return MuscleRecoveryState(
                category: cat,
                lastTrainedDate: lastDate,
                hoursElapsed: hours,
                recoveryHours: recovery
            )
        }
        cachedRecoveryStates = states
        cacheTimestamp = Date()
        return states
    }

    /// Sync version — reads from cache populated by the async path.
    /// Falls back to an empty "all recovered" state if cache is cold (never blocks main thread).
    func getMuscleRecoveryStates() -> [MuscleRecoveryState] {
        if let cached = cachedRecoveryStates,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheTTL {
            return cached
        }
        return MuscleCategory.allCases.map { cat in
            MuscleRecoveryState(
                category: cat,
                lastTrainedDate: nil,
                hoursElapsed: Int.max,
                recoveryHours: Self.recoveryHours[cat] ?? 48
            )
        }
    }

    /// Muscle categories that are ready to train (fully recovered).
    func recoveredMuscles() -> [MuscleCategory] {
        getMuscleRecoveryStates().filter(\.isRecovered).map(\.category)
    }

    /// Async version — uses async Core Data fetch.
    func recoveredMusclesAsync() async -> [MuscleCategory] {
        await getMuscleRecoveryStatesAsync().filter(\.isRecovered).map(\.category)
    }

    // MARK: - Smart Suggestion for Today

    /// Async entry point — fetches recovery data off the main thread.
    @MainActor func suggestForTodayAsync() async -> TodaySuggestion {
        if let programSuggestion = programBasedSuggestion() {
            return programSuggestion
        }
        return await recoveryBasedSuggestionAsync()
    }

    /// Sync entry point — uses cached recovery data (never blocks main thread).
    @MainActor func suggestForToday() -> TodaySuggestion {
        if let programSuggestion = programBasedSuggestion() {
            return programSuggestion
        }
        return recoveryBasedSuggestion()
    }

    // MARK: - Program-Aware Suggestion

    @MainActor private func programBasedSuggestion() -> TodaySuggestion? {
        // 1. Generated program (onboarding-created)
        if let day = GeneratedProgramService.shared.currentDay {
            let muscles = day.focusMuscles.compactMap { canonicalize($0) }
            let family = splitFamilyFor(muscles)
            return TodaySuggestion(
                primaryMessage: "Day \(day.dayNumber) of your program — \(day.focusMuscles.prefix(2).joined(separator: " & "))!",
                suggestedMuscles: muscles.isEmpty ? [.chest, .back] : muscles,
                splitFamily: family,
                isFromProgram: true,
                programDayName: day.name
            )
        }

        // 2. Cloud program
        if let details = CloudProgramService.shared.activeProgramDetails,
           let activeProgram = CloudProgramService.shared.activeProgram {
            let nextDay = activeProgram.currentDay
            if let fullDay = details.days.first(where: { $0.day.dayNumber == nextDay }) {
                let dayInfo = fullDay.day
                if dayInfo.isRestDay {
                    return TodaySuggestion(
                        primaryMessage: "Rest day on your \(details.program.name) program. Recover strong!",
                        suggestedMuscles: [],
                        splitFamily: .fullBody,
                        isFromProgram: true,
                        programDayName: dayInfo.name
                    )
                }
                let muscles = dayInfo.focusAreas.compactMap { canonicalize($0) }
                let family = splitFamilyFor(muscles)
                return TodaySuggestion(
                    primaryMessage: "\(details.program.name) Day \(nextDay): \(dayInfo.name)",
                    suggestedMuscles: muscles.isEmpty ? [.chest, .back] : muscles,
                    splitFamily: family,
                    isFromProgram: true,
                    programDayName: dayInfo.name
                )
            }
        }

        // 3. Smart program engine
        if let activeProgram = SmartProgramEngine.shared.userPrograms.first(where: { !$0.isCompleted }) {
            let day = activeProgram.currentDay
            if let generatedDay = activeProgram.generatedDays.first(where: { $0.dayNumber == day }) {
                let muscles = inferMusclesFromDayName(generatedDay.name)
                let family = splitFamilyFor(muscles)
                return TodaySuggestion(
                    primaryMessage: "Your program: \(generatedDay.name)",
                    suggestedMuscles: muscles.isEmpty ? [.chest, .back] : muscles,
                    splitFamily: family,
                    isFromProgram: true,
                    programDayName: generatedDay.name
                )
            }
        }

        return nil
    }

    // MARK: - Recovery-Based Suggestion (no active program)

    private func recoveryBasedSuggestionAsync() async -> TodaySuggestion {
        let states = await getMuscleRecoveryStatesAsync()
        let recovered = states.filter(\.isRecovered)
        let recentSplits = await getRecentSplitFamiliesAsync(days: 3)
        return buildRecoverySuggestion(states: states, recovered: recovered, recentSplits: recentSplits)
    }

    /// Sync version — uses cached data, never blocks.
    private func recoveryBasedSuggestion() -> TodaySuggestion {
        let states = getMuscleRecoveryStates()
        let recovered = states.filter(\.isRecovered)
        let recentSplits = cachedSplitFamilies ?? []
        return buildRecoverySuggestion(states: states, recovered: recovered, recentSplits: recentSplits)
    }

    private func buildRecoverySuggestion(states: [MuscleRecoveryState], recovered: [MuscleRecoveryState], recentSplits: [SplitFamily]) -> TodaySuggestion {
        let preferredFamilies: [SplitFamily] = [.push, .pull, .legs, .upperBody, .fullBody, .coreCardio]
        let familyCandidates = preferredFamilies.filter { family in
            let muscles = musclesForFamily(family)
            let familyRecovered = muscles.allSatisfy { m in
                recovered.contains { $0.category == m }
            }
            return familyRecovered && !recentSplits.suffix(1).contains(family)
        }

        let chosen = familyCandidates.first ?? bestAvailableFamily(states: states, avoiding: recentSplits)
        let muscles = musclesForFamily(chosen)
        let message = motivationalMessageFor(family: chosen, states: states)

        return TodaySuggestion(
            primaryMessage: message,
            suggestedMuscles: muscles,
            splitFamily: chosen,
            isFromProgram: false,
            programDayName: nil
        )
    }

    private func bestAvailableFamily(states: [MuscleRecoveryState], avoiding recent: [SplitFamily]) -> SplitFamily {
        let familyScores: [(SplitFamily, Double)] = SplitFamily.allCases.map { family in
            let muscles = musclesForFamily(family)
            let avgRecovery = muscles.compactMap { m in
                states.first { $0.category == m }?.recoveryPercent
            }.reduce(0, +) / Double(max(1, muscles.count))

            let recencyPenalty: Double = recent.last == family ? -0.5 : (recent.contains(family) ? -0.2 : 0)
            return (family, avgRecovery + recencyPenalty)
        }
        return familyScores.max(by: { $0.1 < $1.1 })?.0 ?? .fullBody
    }

    // MARK: - Surprise Me Integration

    /// Returns a split family for Surprise Me that avoids the last-generated split.
    /// Call this before selecting the workout split, then call `recordSurpriseSplit` after.
    func surpriseMeExclusion() -> SplitFamily? {
        guard let raw = UserDefaults.standard.string(forKey: lastSurpriseSplitKey),
              let lastFamily = SplitFamily(rawValue: raw),
              let lastDate = UserDefaults.standard.object(forKey: lastSurpriseDateKey) as? Date else {
            return nil
        }
        let hoursSince = Int(Date().timeIntervalSince(lastDate) / 3600)
        if hoursSince < 36 { return lastFamily }
        return nil
    }

    func recordSurpriseSplit(_ family: SplitFamily) {
        UserDefaults.standard.set(family.rawValue, forKey: lastSurpriseSplitKey)
        UserDefaults.standard.set(Date(), forKey: lastSurpriseDateKey)
    }

    /// Maps a Surprise Me split name to a SplitFamily for anti-repetition tracking.
    func classifySplit(muscles: [String]) -> SplitFamily {
        let canonical = muscles.compactMap { canonicalize($0) }
        return splitFamilyFor(canonical)
    }

    // MARK: - Motivational Message Helpers

    /// Async version — fetches recovery data off the main thread, then builds the message.
    @MainActor func contextualMotivationalMessageAsync(firstName: String, crown: String) async -> String? {
        let suggestion = await suggestForTodayAsync()

        if suggestion.isFromProgram {
            if let dayName = suggestion.programDayName {
                let templates = [
                    "\(dayName) day! Stay on track, \(crown)! 🎯",
                    "Your program says \(dayName) — let's get it, \(firstName)! 💪",
                    "Stick to the plan! \(dayName) is calling, \(crown)! 🔥",
                    "Program day: \(dayName). Consistency builds champions! 🏆"
                ]
                return templates.randomElement()
            }
        }

        let states = await getMuscleRecoveryStatesAsync()
        return buildMotivationalMessage(states: states, firstName: firstName, crown: crown)
    }

    /// Sync version — uses cached recovery data for view-body callers.
    @MainActor func contextualMotivationalMessage(firstName: String, crown: String) -> String? {
        let suggestion = suggestForToday()

        if suggestion.isFromProgram {
            if let dayName = suggestion.programDayName {
                let templates = [
                    "\(dayName) day! Stay on track, \(crown)! 🎯",
                    "Your program says \(dayName) — let's get it, \(firstName)! 💪",
                    "Stick to the plan! \(dayName) is calling, \(crown)! 🔥",
                    "Program day: \(dayName). Consistency builds champions! 🏆"
                ]
                return templates.randomElement()
            }
        }

        let states = getMuscleRecoveryStates()
        return buildMotivationalMessage(states: states, firstName: firstName, crown: crown)
    }

    private func buildMotivationalMessage(states: [MuscleRecoveryState], firstName: String, crown: String) -> String? {
        let recovering = states.filter { !$0.isRecovered && $0.lastTrainedDate != nil }
        let bestRecovered = states.filter(\.isRecovered)
            .filter { $0.lastTrainedDate != nil }
            .sorted { $0.hoursElapsed > $1.hoursElapsed }

        if let fresh = bestRecovered.first {
            let name = fresh.category.rawValue.capitalized
            let templates = [
                "\(name) is fully recovered — time to hit it, \(crown)! 💪",
                "Your \(name) is rested and ready! Let's go, \(firstName)! 🔥",
                "\(name) day is \(crown) behavior! 🦵👑"
            ]
            return templates.randomElement()
        }

        if let tired = recovering.sorted(by: { $0.recoveryPercent < $1.recoveryPercent }).first {
            let name = tired.category.rawValue.capitalized
            let percent = Int(tired.recoveryPercent * 100)
            if percent < 50 {
                return "Your \(name) is still recovering (\(percent)%). Work a different group today! 🧘"
            }
        }

        return nil
    }

    /// Returns a smart description for upper/lower body daily quest based on recovery.
    /// Uses cached recovery states — never blocks the main thread.
    @MainActor func smartQuestDescription(isUpperBody: Bool) -> String {
        let states = getMuscleRecoveryStates()

        if isUpperBody {
            let upperMuscles: [MuscleCategory] = [.chest, .back, .shoulders, .biceps, .triceps]
            let recovered = upperMuscles.filter { cat in
                states.first { $0.category == cat }?.isRecovered ?? true
            }
            if recovered.isEmpty {
                return "Upper body is recovering — light session today"
            }
            let names = recovered.prefix(2).map { $0.rawValue.capitalized }
            return "Focus on \(names.joined(separator: " & ")) — they're fresh!"
        } else {
            let lowerMuscles: [MuscleCategory] = [.quads, .hamstrings, .glutes, .calves]
            let recovered = lowerMuscles.filter { cat in
                states.first { $0.category == cat }?.isRecovered ?? true
            }
            if recovered.isEmpty {
                return "Legs are recovering — light session today"
            }
            let names = recovered.prefix(2).map { $0.rawValue.capitalized }
            return "Focus on \(names.joined(separator: " & ")) — they're ready!"
        }
    }

    // MARK: - Helpers

    private func canonicalize(_ raw: String) -> MuscleCategory? {
        Self.muscleAliases[raw.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    /// Infers muscle categories from a workout day name (e.g. "Push Day" → push muscles).
    private func inferMusclesFromDayName(_ name: String) -> [MuscleCategory] {
        let lower = name.lowercased()
        if lower.contains("push") { return [.chest, .shoulders, .triceps] }
        if lower.contains("pull") { return [.back, .biceps] }
        if lower.contains("leg") || lower.contains("lower") { return [.quads, .hamstrings, .glutes, .calves] }
        if lower.contains("chest") && lower.contains("tri") { return [.chest, .triceps] }
        if lower.contains("back") && lower.contains("bi") { return [.back, .biceps] }
        if lower.contains("chest") { return [.chest] }
        if lower.contains("back") { return [.back] }
        if lower.contains("shoulder") || lower.contains("arm") { return [.shoulders, .biceps, .triceps] }
        if lower.contains("core") || lower.contains("ab") { return [.core] }
        if lower.contains("cardio") || lower.contains("hiit") { return [.cardio] }
        if lower.contains("upper") { return [.chest, .back, .shoulders] }
        if lower.contains("full") { return [.chest, .back, .quads, .shoulders] }
        return []
    }

    func musclesForFamily(_ family: SplitFamily) -> [MuscleCategory] {
        switch family {
        case .push:      return [.chest, .shoulders, .triceps]
        case .pull:      return [.back, .biceps]
        case .legs:      return [.quads, .hamstrings, .glutes, .calves]
        case .upperBody: return [.chest, .back, .shoulders, .biceps, .triceps]
        case .fullBody:  return [.chest, .back, .quads, .shoulders]
        case .coreCardio: return [.core, .cardio]
        }
    }

    private func splitFamilyFor(_ muscles: [MuscleCategory]) -> SplitFamily {
        let set = Set(muscles)
        if set.isSubset(of: [.chest, .shoulders, .triceps]) { return .push }
        if set.isSubset(of: [.back, .biceps]) { return .pull }
        if set.isSubset(of: [.quads, .hamstrings, .glutes, .calves]) { return .legs }
        if set.isSubset(of: [.core, .cardio]) { return .coreCardio }
        let lower: Set<MuscleCategory> = [.quads, .hamstrings, .glutes, .calves]
        if !set.intersection(lower).isEmpty && set.intersection([.chest, .back, .shoulders]).isEmpty { return .legs }
        if set.intersection(lower).isEmpty { return .upperBody }
        return .fullBody
    }

    private func motivationalMessageFor(family: SplitFamily, states: [MuscleRecoveryState]) -> String {
        switch family {
        case .push:      return "Push muscles are recovered — chest, shoulders & triceps today!"
        case .pull:      return "Back & biceps are ready! Great pull day ahead."
        case .legs:      return "Legs are fresh — time to build that lower body!"
        case .upperBody: return "Upper body is rested. Go all out today!"
        case .fullBody:  return "Full body session — balanced and effective!"
        case .coreCardio: return "Core & cardio day — keep the engine running!"
        }
    }

    /// Async fetch — runs on the background context queue, never blocks the caller.
    private func getRecentMusclesWithDatesAsync(days: Int) async -> [MuscleCategory: Date] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        return await bgContext.perform {
            var latest: [MuscleCategory: Date] = [:]
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isCompleted == YES"),
                NSPredicate(format: "date >= %@", startDate as NSDate)
            ])
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]

            do {
                let workouts = try self.bgContext.fetch(request)
                for workout in workouts {
                    guard let date = workout.date else { continue }
                    if let exercises = workout.exercises?.allObjects as? [WorkoutExercise] {
                        for ex in exercises {
                            for muscle in ex.safeMuscleGroups {
                                if let cat = self.canonicalize(muscle), latest[cat] == nil {
                                    latest[cat] = date
                                }
                            }
                        }
                    }
                }
            } catch {
                AppLogger.error("WorkoutSuggestionEngine: failed to fetch workouts: \(error.localizedDescription)", category: .workout)
            }
            return latest
        }
    }

    /// Async fetch — runs on the background context queue, never blocks the caller.
    private func getRecentSplitFamiliesAsync(days: Int) async -> [SplitFamily] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let result: [SplitFamily] = await bgContext.perform {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "isCompleted == YES"),
                NSPredicate(format: "date >= %@", startDate as NSDate)
            ])
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: true)]

            do {
                let workouts = try self.bgContext.fetch(request)
                return workouts.map { workout -> SplitFamily in
                    let muscles: [MuscleCategory] = (workout.exercises?.allObjects as? [WorkoutExercise] ?? [])
                        .flatMap { $0.safeMuscleGroups.compactMap { self.canonicalize($0) } }
                    return self.splitFamilyFor(muscles)
                }
            } catch {
                return []
            }
        }
        cachedSplitFamilies = result
        return result
    }
}
