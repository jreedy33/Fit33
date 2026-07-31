import Foundation
import CoreData
import Combine

class MealService: ObservableObject {
    static let shared = MealService()
    
    private let viewContext = PersistenceController.shared.container.viewContext
    private let foodDatabase = FoodDatabaseService.shared
    
    @Published var todaysMeals: [MealEntryData] = []
    @Published var isLoading = false
    
    /// Tracks when todaysMeals was last loaded so we can detect stale (previous-day) data.
    private var lastLoadDate: Date?
    
    private init() {
        // ⚡️ Cold-start speedup Phase 1.5 (2026-04-25):
        // Init still triggers a meal load (so `todaysMeals` is populated by
        // the time the dashboard's nutrition widget renders), but routes
        // through `loadTodaysMealsAsync()` which performs the fetch on a
        // background Core Data context and publishes to `@Published` via a
        // single MainActor hop. Previously this Task hopped to main and ran
        // `viewContext.fetch` synchronously on the main thread during the
        // cold-start contention window.
        Task {
            await self.loadTodaysMealsAsync()
        }
    }
    
    /// Audit PR-18 (2026-07-26): drop the in-memory meal list on sign-out.
    /// Core Data rows are wiped by `clearAllUserData()`, but this published
    /// array would otherwise keep showing the previous user's meals until
    /// the next reload.
    @MainActor
    func resetForSignOut() {
        todaysMeals = []
        lastLoadDate = nil
    }

    /// Ensures todaysMeals is fresh — re-fetches from Core Data if the last load was on a
    /// different calendar day. Call this before any code that reads todaysMeals for syncing
    /// (challenge sync, background sync, etc.) to prevent stale yesterday data from being
    /// pushed as today's progress.
    func ensureFreshForToday() {
        if let lastLoad = lastLoadDate, Calendar.current.isDateInToday(lastLoad) {
            return // Already loaded today — data is fresh
        }
        AppLogger.debug("Data stale (loaded on a different day) — refreshing for today", category: .nutrition)
        loadTodaysMeals()
    }
    
    // MARK: - Public Methods
    
    /// Finding P (2026-07-31): returns whether the entry was actually
    /// persisted. This used to be `Void` with log-only early returns, so
    /// every call site celebrated (haptics, dismiss, confetti) even when
    /// validation or the Core Data save failed.
    @discardableResult
    func addMealEntry(_ foodEntry: FoodEntry, mealType: MealType, user: User) -> Bool {
        // Input validation - return early on invalid data
        let trimmedName = foodEntry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 200 else {
            AppLogger.error("Validation failed: food name must be 1-200 characters", category: .nutrition)
            return false
        }
        guard (0...10000).contains(foodEntry.calories) else {
            AppLogger.error("Validation failed: calories must be 0-10000", category: .nutrition)
            return false
        }
        guard (0...1000).contains(foodEntry.protein) else {
            AppLogger.error("Validation failed: protein must be 0-1000g", category: .nutrition)
            return false
        }
        guard (0...1000).contains(foodEntry.carbs) else {
            AppLogger.error("Validation failed: carbs must be 0-1000g", category: .nutrition)
            return false
        }
        guard (0...1000).contains(foodEntry.fat) else {
            AppLogger.error("Validation failed: fat must be 0-1000g", category: .nutrition)
            return false
        }

        AppLogger.debug("addMealEntry called — Food: \(foodEntry.name), type: \(mealType.rawValue), cal: \(foodEntry.calories), FDC: \(foodEntry.fdcId ?? -1)", category: .nutrition)
        
        let mealEntry = MealEntry(context: viewContext)
        mealEntry.id = UUID()
        mealEntry.foodName = trimmedName
        mealEntry.quantity = foodEntry.quantity   // Now Double end-to-end; preserves fractional servings.
        mealEntry.unit = foodEntry.unit
        mealEntry.calories = Int32(foodEntry.calories)
        mealEntry.protein = Int32(foodEntry.protein)
        mealEntry.carbs = Int32(foodEntry.carbs)
        mealEntry.fat = Int32(foodEntry.fat)
        // fdcId is Int64 in Core Data (widened 2026-04-30 alongside DB
        // `meal_logs.fdc_id` widening in migration #166). OFF rows have
        // synthetic NEGATIVE bigints derived from the barcode; the OLD
        // Int32 column truncated those to 0 on every save → the entire
        // OFF integration silently lost provenance round-trip until this fix.
        mealEntry.fdcId = Int64(foodEntry.fdcId ?? 0)
        mealEntry.fiber = foodEntry.fiber
        mealEntry.sugar = foodEntry.sugar
        mealEntry.sodium = foodEntry.sodium
        mealEntry.source = foodEntry.source
        mealEntry.barcode = foodEntry.barcode
        mealEntry.mealType = mealType.rawValue
        mealEntry.date = Date()
        mealEntry.user = user
        
        do {
            try viewContext.save()
            loadTodaysMeals()
            
            // Sync meal to cloud for cross-device sync
            if SupabaseManager.shared.isAuthenticated {
                Task {
                    do {
                        try await SupabaseManager.shared.saveMealToCloud(meal: mealEntry)
                    } catch {
                        AppLogger.warning("Failed to sync meal to cloud: \(error.localizedDescription)", category: .nutrition)
                    }
                }
            }
            
            // DEPRECATED: logFoodToHistory() wrote duplicate data to user_food_history.
            // meal_logs (written above via saveMealToCloud) is now the single source of truth.
            // The user_food_history_v view derives food history from meal_logs.
            // See: DATABASE_AUDIT_REPORT.md Section 3.2
            
            // Track food addition for recipe recommendations
            // This helps personalize recipe suggestions based on what users eat
            Task { @MainActor in
                RecipePreferenceService.shared.trackFoodAdded(
                    foodName: trimmedName,
                    calories: foodEntry.calories,
                    protein: foodEntry.protein
                )
                
                // Update daily quest progress for meal logging (pass meal type for specific quests)
                await DailyQuestService.shared.onMealLogged(mealType: mealType.rawValue)
                
                // Track high-protein meals (30g+ protein) for quest
                if foodEntry.protein >= 30 {
                    await DailyQuestService.shared.onHighProteinMealLogged()
                }

                // 2026-05-04 — Olympian Path: previously-dormant
                // `BadgeService.onMealLogged` now fires (additive — server
                // increments the lifetime meal counter atomically). Fans out
                // to `first_meal_logged` / `meals_logged_100` and the
                // matching `olympian_<year>_*_meals_*` mirrors so weight-loss
                // and general archetype paths progress on every meal log.
                Task.detached {
                    await BadgeService.shared.incrementAndUnlock(key: "first_meal_logged",  by: 1)
                    await BadgeService.shared.incrementAndUnlock(key: "meals_logged_100",   by: 1)
                    let p = "olympian_\(Calendar.current.component(.year, from: Date()))"
                    await BadgeService.shared.incrementAndUnlock(key: "\(p)_first_meal",    by: 1)
                    await BadgeService.shared.incrementAndUnlock(key: "\(p)_wl_meals_5",    by: 1)
                    await BadgeService.shared.incrementAndUnlock(key: "\(p)_wl_meals_30",   by: 1)
                    await BadgeService.shared.incrementAndUnlock(key: "\(p)_wl_meals_50",   by: 1)
                    await BadgeService.shared.incrementAndUnlock(key: "\(p)_wl_meals_100",  by: 1)
                    await BadgeService.shared.incrementAndUnlock(key: "\(p)_wl_meals_200",  by: 1)
                }
                
                // Update protein goal progress with total today's protein
                let todayProtein = self.todaysMeals.reduce(0) { $0 + $1.protein }
                if todayProtein > 0 {
                    await DailyQuestService.shared.onProteinProgress(totalGrams: todayProtein)
                }
                
                // Award league points for meal logging (+10 pts)
                await WeeklyLeagueService.shared.addPoints(source: .mealLogged)

                // NUJ telemetry — flips `logged_first_meal` boolean on the
                // user's enrollment row via the trigger (#167 contract:
                // event_type='meal' + payload.phase='logged').
                NewUserJourneyTracker.shared.logMeal(
                    phase: "logged",
                    foodName: trimmedName,
                    source: foodEntry.source,
                    calories: Double(foodEntry.calories)
                )
            }
            
            // ⚡ REAL-TIME CHALLENGE SYNC: Push updated protein/calories to ALL challenge types
            Task { @MainActor in
                let totalProtein = todaysMeals.reduce(0) { $0 + $1.protein }
                let totalCalories = todaysMeals.reduce(0) { $0 + $1.calories }
                
                // Sync to 1v1 challenges
                if totalProtein > 0 {
                    await ChallengeService.shared.syncTrackingForType(.protein, value: totalProtein, source: "meals")
                }
                if totalCalories > 0 {
                    await ChallengeService.shared.syncTrackingForType(.calories, value: totalCalories, source: "meals")
                }
                
                // Sync to private challenges
                if totalProtein > 0 {
                    await PrivateChallengeService.shared.syncTrackingForType(.protein, value: totalProtein, source: "meals")
                }
                if totalCalories > 0 {
                    await PrivateChallengeService.shared.syncTrackingForType(.calories, value: totalCalories, source: "meals")
                }
                
                // Sync to community challenges
                if totalProtein > 0 {
                    await CommunityChallengeService.shared.syncTrackingForType(.protein, value: totalProtein, source: "meals")
                }
                if totalCalories > 0 {
                    await CommunityChallengeService.shared.syncTrackingForType(.calories, value: totalCalories, source: "meals")
                }
            }
        } catch {
            AppLogger.error("Error saving meal entry: \(error.localizedDescription)", category: .nutrition)
            // The unsaved MealEntry would otherwise linger in viewContext
            // and be swept into the NEXT successful save.
            viewContext.delete(mealEntry)
            return false
        }
        return true
    }
    
    func removeMealEntry(_ mealEntryData: MealEntryData) {
        AppLogger.debug("Removing meal: \(mealEntryData.foodName)", category: .nutrition)
        
        let request: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", mealEntryData.id as CVarArg)
        
        do {
            let results = try viewContext.fetch(request)
            if let mealEntry = results.first {
                // Delete from local Core Data
                viewContext.delete(mealEntry)
                try viewContext.save()
                loadTodaysMeals()
                AppLogger.info("Successfully deleted meal from local database", category: .nutrition)
                
                // Also delete from cloud to prevent reappearing on sync
                if SupabaseManager.shared.isAuthenticated {
                    Task {
                        do {
                            try await SupabaseManager.shared.deleteMealFromCloud(mealId: mealEntryData.id)
                            AppLogger.info("Successfully deleted meal from cloud", category: .nutrition)
                            
                            // Also remove from food history so it doesn't affect "frequently used"
                            await foodDatabase.removeFromFoodHistory(
                                fdcId: mealEntryData.fdcId,
                                foodName: mealEntryData.foodName
                            )
                        } catch {
                            AppLogger.warning("Failed to delete meal from cloud: \(error.localizedDescription)", category: .nutrition)
                        }
                    }
                }
                
                // ⚡ Re-sync challenge progress with updated (lower) totals.
                // allowDecrease: true tells the DB to accept the lower value and
                // fire a realtime event so the opponent sees the change immediately.
                Task { @MainActor in
                    let totalProtein = todaysMeals.reduce(0) { $0 + $1.protein }
                    let totalCalories = todaysMeals.reduce(0) { $0 + $1.calories }
                    
                    // Sync to 1v1 challenges (with decrease support)
                    await ChallengeService.shared.syncTrackingForType(.protein, value: totalProtein, source: "meals", allowDecrease: true)
                    await ChallengeService.shared.syncTrackingForType(.calories, value: totalCalories, source: "meals", allowDecrease: true)
                    
                    // Sync to private challenges (allowDecrease so DB accepts the lower value)
                    await PrivateChallengeService.shared.syncTrackingForType(.protein, value: totalProtein, source: "meals", allowDecrease: true)
                    await PrivateChallengeService.shared.syncTrackingForType(.calories, value: totalCalories, source: "meals", allowDecrease: true)
                    
                    // Sync to community challenges (allowDecrease so DB accepts the lower value)
                    await CommunityChallengeService.shared.syncTrackingForType(.protein, value: totalProtein, source: "meals", allowDecrease: true)
                    await CommunityChallengeService.shared.syncTrackingForType(.calories, value: totalCalories, source: "meals", allowDecrease: true)
                }
            }
        } catch {
            AppLogger.error("Error removing meal entry: \(error.localizedDescription)", category: .nutrition)
        }
    }
    
    func clearAllMeals() {
        AppLogger.debug("Clearing ALL meal entries from Core Data", category: .nutrition)
        let request: NSFetchRequest<NSFetchRequestResult> = MealEntry.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        do {
            try viewContext.execute(deleteRequest)
            try viewContext.save()
            todaysMeals = []
            AppLogger.info("Successfully cleared all meals", category: .nutrition)
        } catch {
            AppLogger.error("Error clearing meals: \(error.localizedDescription)", category: .nutrition)
        }
    }
    
    // MARK: - Historical Data (for dashboards/analytics)
    
    /// Get daily nutrition summary for a specific date
    func getDailySummary(for date: Date) -> (calories: Int, protein: Int, carbs: Int, fat: Int, mealCount: Int) {
        let meals = getMealsForDate(date)
        return (
            calories: meals.reduce(0) { $0 + $1.calories },
            protein: meals.reduce(0) { $0 + $1.protein },
            carbs: meals.reduce(0) { $0 + $1.carbs },
            fat: meals.reduce(0) { $0 + $1.fat },
            mealCount: meals.count
        )
    }
    
    /// Get nutrition data for last N days (for charts/graphs)
    func getWeeklySummary(days: Int = 7) -> [(date: Date, calories: Int, protein: Int, carbs: Int, fat: Int)] {
        var summaries: [(Date, Int, Int, Int, Int)] = []
        let calendar = Calendar.current
        
        for dayOffset in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let summary = getDailySummary(for: date)
                summaries.append((date, summary.calories, summary.protein, summary.carbs, summary.fat))
            }
        }
        
        return summaries.reversed() // Oldest to newest
    }
    
    func loadTodaysMeals() {
        isLoading = true
        lastLoadDate = Date()   // Track when we loaded so ensureFreshForToday() can detect staleness
        
        let request: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        AppLogger.debug("Loading meals for today (\(startOfDay) – \(endOfDay))", category: .nutrition)
        
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MealEntry.date, ascending: true)]
        
        do {
            let results = try viewContext.fetch(request)
            AppLogger.debug("Found \(results.count) meal entries for today", category: .nutrition)
            
            todaysMeals = results.map { mealEntry in
                let data = mealEntry.toMealEntryData()
                AppLogger.verbose("  - \(data.foodName): \(data.calories)cal, \(data.protein)p, \(data.carbs)c, \(data.fat)f (\(data.mealType.rawValue))", category: .nutrition)
                return data
            }
            
            let totalCals = todaysMeals.reduce(0) { $0 + $1.calories }
            let totalProtein = todaysMeals.reduce(0) { $0 + $1.protein }
            let totalCarbs = todaysMeals.reduce(0) { $0 + $1.carbs }
            let totalFat = todaysMeals.reduce(0) { $0 + $1.fat }
            
            AppLogger.debug("Today's totals: \(totalCals)cal, \(totalProtein)p, \(totalCarbs)c, \(totalFat)f", category: .nutrition)
            
            // 🧠 ADVANCED INTELLIGENCE: Track nutrition for performance correlation
            // This links today's nutrition to tomorrow's workout performance
            if SupabaseManager.shared.isAuthenticated, let userId = SupabaseManager.shared.currentUser?.id {
                Task {
                    await AdvancedIntelligenceService.shared.trackNutritionPerformanceLink(
                        userId: userId,
                        date: Date(),
                        calories: totalCals,
                        protein: totalProtein,
                        carbs: totalCarbs,
                        fat: totalFat,
                        mealsLogged: todaysMeals.count
                    )
                }
            }
        } catch {
            AppLogger.error("Error loading today's meals: \(error.localizedDescription)", category: .nutrition)
            todaysMeals = []
        }
        
        isLoading = false
    }

    /// Async variant used by `init()` so the cold-start meal load never
    /// blocks the main thread. Heavy fetch + DTO conversion runs on a
    /// background context, with a single `MainActor` publish at the end.
    /// Sprint 2026-04-25 (cold-start speedup Phase 1.5).
    private func loadTodaysMealsAsync() async {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let results: [MealEntryData] = await bgContext.perform {
            let request: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
            request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \MealEntry.date, ascending: true)]
            do {
                let entries = try bgContext.fetch(request)
                return entries.map { $0.toMealEntryData() }
            } catch {
                AppLogger.error("Error loading today's meals (bg): \(error.localizedDescription)", category: .nutrition)
                return []
            }
        }

        await MainActor.run {
            self.todaysMeals = results
            self.lastLoadDate = Date()
            self.isLoading = false
        }
    }

    func getMealsForDate(_ date: Date) -> [MealEntryData] {
        let request: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MealEntry.date, ascending: true)]
        
        do {
            let results = try viewContext.fetch(request)
            return results.map { $0.toMealEntryData() }
        } catch {
            AppLogger.error("Error loading meals for date: \(error.localizedDescription)", category: .nutrition)
            return []
        }
    }

    /// Lifetime meal rows on-device — used by `BadgeService.resyncOlympianProgressFromLocalTotals`
    /// so Olympian nutrition goals catch up after Path opens (retroactive progress).
    func lifetimeMealEntryCount() -> Int {
        let request: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
        do {
            return try viewContext.count(for: request)
        } catch {
            AppLogger.warning("lifetimeMealEntryCount failed: \(error.localizedDescription)", category: .nutrition)
            return 0
        }
    }
    
    func getTotalNutritionForDate(_ date: Date) -> DayNutritionSummary {
        let meals = getMealsForDate(date)
        
        let totalCalories = meals.reduce(0) { $0 + $1.calories }
        let totalProtein = meals.reduce(0) { $0 + $1.protein }
        let totalCarbs = meals.reduce(0) { $0 + $1.carbs }
        let totalFat = meals.reduce(0) { $0 + $1.fat }
        
        return DayNutritionSummary(
            date: date,
            totalCalories: totalCalories,
            totalProtein: totalProtein,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            meals: meals
        )
    }
    
    func getNutritionHistory(days: Int = 7) -> [DayNutritionSummary] {
        let calendar = Calendar.current
        var summaries: [DayNutritionSummary] = []
        
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let summary = getTotalNutritionForDate(date)
                summaries.append(summary)
            }
        }
        
        return summaries.reversed() // Most recent first
    }
}

// MARK: - Data Models

struct MealEntryData: Identifiable {
    let id: UUID
    let foodName: String
    let quantity: Double
    let unit: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let mealType: MealType
    let date: Date
    let fdcId: Int // For favoriting functionality (Int64 on 64-bit; supports OFF negatives)
    // Detailed nutrition (added 2026-04-30) — defaults to 0 so legacy MealEntry
    // rows (created before fiber/sugar/sodium attributes existed) still load
    // cleanly under Core Data lightweight migration.
    var fiber: Double = 0
    var sugar: Double = 0
    var sodium: Double = 0
    // Provenance (added 2026-04-30 with OFF). Nil for pre-OFF rows.
    var source: String? = nil
    var barcode: String? = nil

    var displayQuantity: String {
        if quantity == floor(quantity) {
            return String(Int(quantity))
        } else {
            return String(format: "%.1f", quantity)
        }
    }
}

// MARK: - MealEntry → MealEntryData mapper
//
// Single canonical mapper used by all three load paths
// (`loadTodaysMeals`, `loadTodaysMealsAsync`, `getMealsForDate`).
// Replaces three near-identical inline initializers that drifted whenever
// a new column was added (the 2026-04-30 nutrition audit found that
// adding fiber/sugar/sodium without a single mapper would have required
// hand-editing all three sites and still missed the fix in any future load
// path).
extension MealEntry {
    func toMealEntryData() -> MealEntryData {
        var data = MealEntryData(
            id: id ?? UUID(),
            foodName: foodName ?? "",
            quantity: quantity,
            unit: unit ?? "",
            calories: Int(calories),
            protein: Int(protein),
            carbs: Int(carbs),
            fat: Int(fat),
            mealType: MealType(rawValue: mealType ?? "") ?? .breakfast,
            date: date ?? Date(),
            fdcId: Int(fdcId)
        )
        // Detailed nutrition + provenance — populated 2026-04-30 with OFF.
        // Legacy rows return 0 / nil from Core Data which is the correct
        // semantic for "we don't know" (vs a real zero like a true 0g sugar food).
        data.fiber = fiber
        data.sugar = sugar
        data.sodium = sodium
        data.source = source
        data.barcode = barcode
        return data
    }
}

struct DayNutritionSummary {
    let date: Date
    let totalCalories: Int
    let totalProtein: Int
    let totalCarbs: Int
    let totalFat: Int
    let meals: [MealEntryData]
    
    var mealsByType: [MealType: [MealEntryData]] {
        Dictionary(grouping: meals, by: { $0.mealType })
    }
    
    var caloriesByMealType: [MealType: Int] {
        var result: [MealType: Int] = [:]
        for mealType in MealType.allCases {
            result[mealType] = mealsByType[mealType]?.reduce(0) { $0 + $1.calories } ?? 0
        }
        return result
    }
}
