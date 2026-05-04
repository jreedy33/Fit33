import SwiftUI
import CoreData

// Q2-78 (Sprint 8): Hoisted day-header formatter shared across the three day
// section variants below — avoids allocating a `DateFormatter` on every row.
private let workoutHistoryDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE, MMMM d"
    return f
}()

// MARK: - Workout History Full View (Full Page Navigation)
struct WorkoutHistoryFullView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    // Full history page already paginates via scrolling UI; cap the Core Data
    // fetch at 500 rows so a long-time user doesn't page in their entire
    // lifetime on first render. Per QP invariant #3.
    @FetchRequest(fetchRequest: {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
        request.predicate = NSPredicate(format: "isCompleted == true")
        request.fetchLimit = 500
        return request
    }(), animation: .none)
    private var allWorkouts: FetchedResults<Workout>
    
    @StateObject private var adManager = AdManager.shared
    @ObservedObject private var premiumManager = PremiumManager.shared
    @State private var cardioWorkouts: [CardioWorkoutDTO] = []
    @State private var showHistoryUnlockPaywall = false

    /// Phase 2 monetization (2026-05-03): Free users see the last 30
    /// days of history. Pro users see everything. The paywall surfaces
    /// AFTER the 30-day cutoff with a "Unlock Unlimited History" banner
    /// — never silently truncates without an upsell. Pro Preview also
    /// passes (silent until MON-14).
    private static let freeHistoryDays: Int = 30
    private var freeHistoryCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -Self.freeHistoryDays, to: Date()) ?? .distantPast
    }
    private var historyCapApplies: Bool {
        !premiumManager.isPremiumUser && !MonetizationState.shared.isInProPreview
    }
    
    enum HistoryItem: Identifiable {
        case strength(Workout)
        case cardio(CardioWorkoutDTO)
        
        var id: String {
            switch self {
            case .strength(let w): return "s-\(w.objectID.uriRepresentation().absoluteString)"
            case .cardio(let c): return "c-\(c.id)"
            }
        }
        
        var date: Date {
            switch self {
            case .strength(let w): return w.date ?? Date.distantPast
            case .cardio(let c): return ISO8601Parser.parse(c.completedAt, fallback: Date.distantPast)
            }
        }
    }
    
    /// Merged view of `allWorkouts` + `cardioWorkouts`. Wearable-origin
    /// strength cardio rows that time-overlap a Fit33 strength workout are
    /// collapsed into the Fit33 row (see `WorkoutWearableMerger`). The
    /// wearable's metrics are surfaced via `enrichmentByWorkoutID` so the
    /// card / detail view can show the HR + origin badge.
    private var mergedCardio: WorkoutWearableMerger.Result {
        WorkoutWearableMerger.merge(
            strength: Array(allWorkouts),
            cardio: cardioWorkouts
        )
    }

    private var groupedItems: [(Date, [HistoryItem])] {
        let calendar = Calendar.current
        let merged = mergedCardio
        var items: [HistoryItem] = allWorkouts.map { .strength($0) }
        items.append(contentsOf: merged.filteredCardio.map { .cardio($0) })

        // Apply 30-day free-tier cap (Phase 2 monetization). The
        // truncated rows still exist in Core Data — they just don't
        // render. The paywall banner below the list nudges to unlock.
        if historyCapApplies {
            let cutoff = freeHistoryCutoff
            items = items.filter { $0.date >= cutoff }
        }

        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    /// Number of pre-cap items hidden from the free tier — drives the
    /// upsell banner copy ("View 47 more workouts with Pro →").
    private var hiddenItemsCount: Int {
        guard historyCapApplies else { return 0 }
        let cutoff = freeHistoryCutoff
        let strengthHidden = allWorkouts.filter { ($0.date ?? .distantPast) < cutoff }.count
        let cardioHidden = mergedCardio.filteredCardio.filter {
            ISO8601Parser.parse($0.completedAt, fallback: .distantPast) < cutoff
        }.count
        return strengthHidden + cardioHidden
    }

    private var totalWorkouts: Int { allWorkouts.count + mergedCardio.filteredCardio.count }
    private var totalExercises: Int {
        allWorkouts.reduce(0) { $0 + (($1.exercises?.count) ?? 0) }
    }
    private var totalDuration: TimeInterval {
        // Use merged cardio list so a wearable strength session isn't
        // double-counted against the Fit33 workout it overlaps with.
        let strengthTime = allWorkouts.reduce(0.0) { $0 + Double($1.duration) }
        let cardioTime = mergedCardio.filteredCardio.reduce(0.0) { $0 + Double($1.durationSeconds) }
        return strengthTime + cardioTime
    }

    private var totalCalories: Int {
        // When a wearable recorded a Fit33 session (merged via overlap dedup),
        // swap the Fit33 MET-formula estimate for the wearable's measured
        // value — it's materially more accurate and is what's shown on the
        // individual card / detail view, so header totals must agree.
        let merged = mergedCardio
        let strengthCals = allWorkouts.reduce(0.0) { partial, workout in
            partial + WorkoutWearableMerger.effectiveCalories(
                workout: workout,
                wearable: workout.id.flatMap { merged.enrichmentByWorkoutID[$0] }
            )
        }
        let cardioCals = merged.filteredCardio.reduce(0.0) { $0 + $1.caloriesBurned }
        return Int(strengthCals + cardioCals)
    }
    
    var body: some View {
        ZStack {
            AdaptiveGradient.home(for: colorScheme)
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    statsHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    
                    if groupedItems.isEmpty {
                        emptyStateView
                            .padding(.horizontal, 20)
                    } else {
                        let wearableMap = mergedCardio.enrichmentByWorkoutID
                        LazyVStack(spacing: 20) {
                            ForEach(Array(groupedItems.enumerated()), id: \.offset) { _, dayGroup in
                                WorkoutHistoryDaySectionCombined(
                                    date: dayGroup.0,
                                    items: dayGroup.1,
                                    showAds: adManager.adsEnabled,
                                    wearableEnrichment: wearableMap
                                )
                                .padding(.horizontal, 20)
                            }
                        }

                        if hiddenItemsCount > 0 {
                            unlockHistoryBanner
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadCardioWorkouts()
        }
        .fullScreenCover(isPresented: $showHistoryUnlockPaywall) {
            PremiumUpgradeView(triggeringFeature: .unlimitedHistory)
        }
    }

    /// Free-tier 30-day-cap upsell banner. Sits below the visible
    /// workout history. Always personalized ("X more workouts behind
    /// the cutoff") so the user knows there's real value to unlock,
    /// not just abstract Pro features.
    private var unlockHistoryBanner: some View {
        Button {
            HapticManager.impact(.light)
            showHistoryUnlockPaywall = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.ds_bodyRegular)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hiddenItemsCount) more workouts behind the cutoff")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Free shows last 30 days · Pro unlocks your full history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Unlock")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)))
            }
            .padding(14)
            .background(AdaptiveCardSurface(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func loadCardioWorkouts() async {
        do {
            let workouts = try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 100)
            await MainActor.run { self.cardioWorkouts = workouts }
        } catch {
            AppLogger.warning("Failed to load cardio history: \(error.localizedDescription)", category: .ui)
        }
    }
    
    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 12) {
            HistoryStatPill(icon: "dumbbell.fill", value: "\(totalWorkouts)", label: "Workouts", color: .blue)
            HistoryStatPill(icon: "flame.fill", value: formatCalories(totalCalories), label: "Calories", color: .orange)
            HistoryStatPill(icon: "clock.fill", value: formatTotalDuration(), label: "Total Time", color: .green)
        }
    }
    
    private func formatCalories(_ calories: Int) -> String {
        if calories >= 1000 {
            return String(format: "%.1fk", Double(calories) / 1000.0)
        }
        return "\(calories)"
    }
    
    private func formatTotalDuration() -> String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 3
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.ds_heading1)
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Workouts Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Complete your first workout to see it here!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .background(AdaptiveCardSurface(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 12, x: 0, y: 6)
    }
}

// MARK: - History Stat Pill
struct HistoryStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.ds_labelMedium)
                    .foregroundColor(color)
                Text(value)
                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(AdaptiveCardSurface(cornerRadius: CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - Workout History Day Section With Ads
struct WorkoutHistoryDaySectionWithAds: View {
    let date: Date
    let workouts: [Workout]
    let showAds: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayDate: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return workoutHistoryDayFormatter.string(from: date)
        }
    }
    
    // Calculate total items including ads
    private var totalItemsWithAds: Int {
        guard showAds else { return workouts.count }
        let workoutCount = workouts.count
        let adCount = workoutCount / 2 // Ad after every 2 workouts
        return workoutCount + adCount
    }
    
    // Native ad cadence: every 4th display position (positions 3, 7,
    // 11...). Tightened from `% 3` to `% 4` (Phase 1, 2026-05-03
    // monetization sweep) — matches the ad-load best practice from
    // Strong/Hevy/MyFitnessPal: lower density per scroll = higher
    // CTR per impression + lower uninstall rate. Net eCPM lift > 0
    // even with 25% fewer impressions.
    private func isAdPosition(_ index: Int) -> Bool {
        guard showAds else { return false }
        return (index + 1) % 4 == 0
    }

    // Get the actual workout index accounting for ads
    private func getWorkoutIndex(for displayIndex: Int) -> Int {
        guard showAds else { return displayIndex }
        let adsBeforeThisIndex = displayIndex / 4
        return displayIndex - adsBeforeThisIndex
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(displayDate)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(workouts.count) workout\(workouts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, Spacing.xxs)
            
            // Workout cards with ads inserted
            VStack(spacing: 12) {
                ForEach(0..<totalItemsWithAds, id: \.self) { index in
                    if isAdPosition(index) && showAds {
                        // Native ad card
                        NativeAdCardView()
                    } else {
                        // Workout card
                        let workoutIndex = getWorkoutIndex(for: index)
                        if workoutIndex < workouts.count {
                            RecentWorkoutCard(workout: workouts[workoutIndex])
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Combined Workout History Day Section (strength + cardio)
struct WorkoutHistoryDaySectionCombined: View {
    let date: Date
    let items: [WorkoutHistoryFullView.HistoryItem]
    let showAds: Bool
    /// Map of Fit33 `Workout.id` → wearable cardio row that overlapped it.
    /// Populated by `WorkoutWearableMerger`. When a strength item's UUID is
    /// present, `RecentWorkoutCard` renders a small wearable origin chip.
    var wearableEnrichment: [UUID: CardioWorkoutDTO] = [:]
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayDate: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return workoutHistoryDayFormatter.string(from: date)
        }
    }
    
    private var sortedItems: [WorkoutHistoryFullView.HistoryItem] {
        items.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(displayDate)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(items.count) workout\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, Spacing.xxs)
            
            VStack(spacing: 12) {
                ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                    if showAds && index > 0 && index % 4 == 0 {
                        NativeAdCardView()
                    }
                    
                    switch item {
                    case .strength(let workout):
                        RecentWorkoutCard(
                            workout: workout,
                            wearableEnrichment: workout.id.flatMap { wearableEnrichment[$0] }
                        )
                    case .cardio(let cardio):
                        RecentCardioWorkoutCard(cardioWorkout: cardio)
                    }
                }
            }
        }
    }
}

// MARK: - Workout History Day Section (Legacy - kept for compatibility)
struct WorkoutHistoryDaySection: View {
    let date: Date
    let workouts: [Workout]
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayDate: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return workoutHistoryDayFormatter.string(from: date)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(displayDate)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(workouts.count) workout\(workouts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, Spacing.xxs)
            
            // Workout cards - using same style as home page
            VStack(spacing: 12) {
                ForEach(workouts, id: \.id) { workout in
                    RecentWorkoutCard(workout: workout)
                }
            }
        }
    }
}
