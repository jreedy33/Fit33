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
    
    func addMealEntry(_ foodEntry: FoodEntry, mealType: MealType, user: User) {
        // Input validation - return early on invalid data
        let trimmedName = foodEntry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 200 else {
            AppLogger.error("Validation failed: food name must be 1-200 characters", category: .nutrition)
            return
        }
        guard (0...10000).contains(foodEntry.calories) else {
            AppLogger.error("Validation failed: calories must be 0-10000", category: .nutrition)
            return
        }
        guard (0...1000).contains(foodEntry.protein) else {
            AppLogger.error("Validation failed: protein must be 0-1000g", category: .nutrition)
            return
        }
        guard (0...1000).contains(foodEntry.carbs) else {
            AppLogger.error("Validation failed: carbs must be 0-1000g", category: .nutrition)
            return
        }
        guard (0...1000).contains(foodEntry.fat) else {
            AppLogger.error("Validation failed: fat must be 0-1000g", category: .nutrition)
            return
        }

        AppLogger.debug("addMealEntry called — Food: \(foodEntry.name), type: \(mealType.rawValue), cal: \(foodEntry.calories), FDC: \(foodEntry.fdcId ?? -1)", category: .nutrition)
        
        let mealEntry = MealEntry(context: viewContext)
        mealEntry.id = UUID()
        mealEntry.foodName = trimmedName
        mealEntry.quantity = Double(foodEntry.quantity)
        mealEntry.unit = foodEntry.unit
        mealEntry.calories = Int32(foodEntry.calories)
        mealEntry.protein = Int32(foodEntry.protein)
        mealEntry.carbs = Int32(foodEntry.carbs)
        mealEntry.fat = Int32(foodEntry.fat)
        mealEntry.fdcId = Int32(foodEntry.fdcId ?? 0)
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
                
                // Update protein goal progress with total today's protein
                let todayProtein = self.todaysMeals.reduce(0) { $0 + $1.protein }
                if todayProtein > 0 {
                    await DailyQuestService.shared.onProteinProgress(totalGrams: todayProtein)
                }
                
                // Award league points for meal logging (+10 pts)
                await WeeklyLeagueService.shared.addPoints(source: .mealLogged)
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
        }
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
                let data = MealEntryData(
                    id: mealEntry.id ?? UUID(),
                    foodName: mealEntry.foodName ?? "",
                    quantity: mealEntry.quantity,
                    unit: mealEntry.unit ?? "",
                    calories: Int(mealEntry.calories),
                    protein: Int(mealEntry.protein),
                    carbs: Int(mealEntry.carbs),
                    fat: Int(mealEntry.fat),
                    mealType: MealType(rawValue: mealEntry.mealType ?? "") ?? .breakfast,
                    date: mealEntry.date ?? Date(),
                    fdcId: Int(mealEntry.fdcId)
                )
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
                return entries.map { mealEntry in
                    MealEntryData(
                        id: mealEntry.id ?? UUID(),
                        foodName: mealEntry.foodName ?? "",
                        quantity: mealEntry.quantity,
                        unit: mealEntry.unit ?? "",
                        calories: Int(mealEntry.calories),
                        protein: Int(mealEntry.protein),
                        carbs: Int(mealEntry.carbs),
                        fat: Int(mealEntry.fat),
                        mealType: MealType(rawValue: mealEntry.mealType ?? "") ?? .breakfast,
                        date: mealEntry.date ?? Date(),
                        fdcId: Int(mealEntry.fdcId)
                    )
                }
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
            return results.map { mealEntry in
                MealEntryData(
                    id: mealEntry.id ?? UUID(),
                    foodName: mealEntry.foodName ?? "",
                    quantity: mealEntry.quantity,
                    unit: mealEntry.unit ?? "",
                    calories: Int(mealEntry.calories),
                    protein: Int(mealEntry.protein),
                    carbs: Int(mealEntry.carbs),
                    fat: Int(mealEntry.fat),
                    mealType: MealType(rawValue: mealEntry.mealType ?? "") ?? .breakfast,
                    date: mealEntry.date ?? Date(),
                    fdcId: Int(mealEntry.fdcId)
                )
            }
        } catch {
            AppLogger.error("Error loading meals for date: \(error.localizedDescription)", category: .nutrition)
            return []
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
    let fdcId: Int // For favoriting functionality
    
    var displayQuantity: String {
        if quantity == floor(quantity) {
            return String(Int(quantity))
        } else {
            return String(format: "%.1f", quantity)
        }
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
