import SwiftUI
import CoreData

// Q2-78 (Sprint 8): hoist `DateFormatter` / `ISO8601DateFormatter` instances so
// day-picker, streak, and history card renders don't re-allocate formatters on
// every body evaluation.
private let hydrationDayOfWeekShortFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "E"
    return f
}()
private let hydrationDayOfWeekFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE"
    return f
}()
private let hydrationYMDFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()
private let hydrationMonthDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()
private let hydrationShortTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    return f
}()
private let hydrationISO8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

// MARK: - Water Intake Widget
struct HydrationWidget: View {
    @StateObject private var hydrationService = HydrationService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAddSheet = false
    @State private var showingDetailView = false
    @State private var animateRing = false
    @State private var showCelebration = false
    @State private var showingInfoPopup = false
    @State private var selectedCard: Int = 0

    // 2026-05-08 (Bug-intel shake `6d2dd20f` + `5faa0cc4` — Joe Reed:
    // "on the hydration toggle, in the top right there should be a oz/ml
    // toggle that the user can switch between depending on their preferred
    // units"): unit preference shared with `AddWaterSheet` (line ~423)
    // and `DashboardHydrationWidget` via the canonical AppStorage key
    // `hydrationUnitPreference` so toggling here flips both surfaces in
    // lockstep. The widget body uses `formatVolume(...)` everywhere
    // ml/oz display matters; storage stays canonical ml.
    @AppStorage("hydrationUnitPreference") private var usesOz: Bool = true

    private static let mlPerOz = 29.5735

    /// Quick-add chip amounts in oz when `usesOz == true`; tap converts to ml via `Self.mlPerOz`.
    private let widgetOzQuickPresets: [Int] = [8, 12, 16, 24]
    
    private var progress: Double {
        hydrationService.todayProgress
    }
    
    private var totalMl: Int {
        hydrationService.todayTotal
    }
    
    private var goalMl: Int {
        hydrationService.settings.dailyGoalMl
    }
    
    private var remainingMl: Int {
        hydrationService.todayRemaining
    }
    
    private var goalMet: Bool {
        hydrationService.todayGoalMet
    }
    
    private let gradientColors: [Color] = [.cyan, .blue]
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Hydration")
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { HapticManager.selectionChanged(); showingDetailView = true }) {
                    HStack(spacing: Spacing.xxs) {
                        Text("Details")
                            .font(.ds_labelMedium)
                        Image(systemName: "chevron.right")
                            .font(.ds_caption)
                    }
                    .foregroundColor(.blue)
                }
                .accessibilityLabel("Hydration details")
                .accessibilityHint("Opens detailed hydration history")
            }
            .padding(.horizontal, Spacing.xxs)
            
            // Card body
            VStack(spacing: 0) {
                // Top: insight or action
                HStack(spacing: 8) {
                    if totalMl == 0 {
                        Text("Tap + to start tracking water today")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                    } else if goalMet {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(.green)
                        Text("Goal reached! \(daysMetGoal)/7 days this week")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "drop.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(.cyan)
                        Text("\(formatMl(remainingMl)) to go • \(daysMetGoal)/7 days this week")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    // Oz/ml toggle lives on the card surface (shared AppStorage with AddWaterSheet + dashboard).
                    unitToggle
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                // Content row
                HStack(spacing: 14) {
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: animateRing ? progress : 0)
                            .stroke(
                                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 0) {
                            Text("\(Int(progress * 100))")
                                .font(.ds_labelLarge).fontDesign(.rounded)
                            Text("%")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                            Text(formatMl(totalMl))
                                .font(.ds_statSmall)
                                .foregroundStyle(
                                    LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                                )
                            Text("/ \(formatMl(goalMl))")
                                .font(.ds_caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Quick add presets — labels + tap amounts follow `usesOz` (storage stays canonical ml).
                        HStack(spacing: Spacing.xxs) {
                            if usesOz {
                                ForEach(widgetOzQuickPresets, id: \.self) { oz in
                                    let amountMl = Int(Double(oz) * Self.mlPerOz)
                                    Button {
                                        HapticManager.impact(.light)
                                        Task {
                                            let success = await hydrationService.logWater(amountMl: amountMl)
                                            if success && hydrationService.todayGoalMet {
                                                showCelebration = true
                                            }
                                        }
                                    } label: {
                                        Text("\(oz) oz")
                                            .font(.ds_caption)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Spacing.xxs)
                                            .background(Color.blue.opacity(0.08))
                                            .cornerRadius(CornerRadius.sm)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            } else {
                                ForEach(Array(WaterPreset.presets.prefix(4))) { preset in
                                    Button {
                                        HapticManager.impact(.light)
                                        Task {
                                            let success = await hydrationService.logWater(amountMl: preset.amountMl)
                                            if success && hydrationService.todayGoalMet {
                                                showCelebration = true
                                            }
                                        }
                                    } label: {
                                        Text("\(preset.amountMl) ml")
                                            .font(.ds_caption)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Spacing.xxs)
                                            .background(Color.blue.opacity(0.08))
                                            .cornerRadius(CornerRadius.sm)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        
                        // Weekly mini bar chart
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(0..<7, id: \.self) { index in
                                let dayData = weeklyDataForIndex(index)
                                let isToday = index == 6
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        dayData.goalMet
                                            ? LinearGradient(colors: [.green, .mint], startPoint: .bottom, endPoint: .top)
                                            : LinearGradient(colors: [.cyan, .blue.opacity(0.5)], startPoint: .bottom, endPoint: .top)
                                    )
                                    .frame(height: max(3, 20 * min(dayData.progress, 1.0)))
                                    .frame(maxWidth: .infinity)
                                    .opacity(isToday ? 1 : 0.7)
                            }
                        }
                        .frame(height: 20)
                    }
                    
                    Button(action: { HapticManager.impact(.medium); showingAddSheet = true }) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 36, height: 36)
                            Image(systemName: "plus")
                                .font(.ds_bodySmall).fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    .scaleButtonStyle(.standard, withHaptic: true)
                    .accessibilityLabel("Add water")
                    .accessibilityHint("Opens water intake entry")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .background(compactCardBackground)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
            .shadow(color: Color.cyan.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 16, x: 0, y: 0)
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                animateRing = true
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWaterSheet(hydrationService: hydrationService)
        }
        .sheet(isPresented: $showingDetailView) {
            WaterIntakeDetailView(hydrationService: hydrationService)
        }
        .overlay {
            if showCelebration {
                GoalCelebrationOverlay(showCelebration: $showCelebration)
            }
        }
        .sheet(isPresented: $showingInfoPopup) {
            WaterGoalInfoSheet(goalMl: hydrationService.settings.dailyGoalMl)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Header
    // MARK: - Shared Card Background
    private var compactCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.18), Color.cardBackground]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        }
    }
    
    private var daysMetGoal: Int {
        hydrationService.weeklyData.filter { $0.goalMet }.count
    }
    
    private var bestDayMl: Int {
        hydrationService.weeklyData.map { $0.totalMl }.max() ?? 0
    }
    
    private func formatMlShort(_ ml: Int) -> String {
        if ml >= 1000 {
            return String(format: "%.1fL", Double(ml) / 1000.0)
        }
        return "\(ml)"
    }
    
    private func calculateWeeklyAverage() -> Int {
        let data = hydrationService.weeklyData
        guard !data.isEmpty else { return 0 }
        let total = data.reduce(0) { $0 + $1.totalMl }
        return total / data.count
    }
    
    private func calculateMonthlyAverage() -> Int? {
        let data = hydrationService.weeklyData
        guard !data.isEmpty else { return nil }
        let total = data.reduce(0) { $0 + $1.totalMl }
        return total / data.count
    }
    
    private func weeklyDataForIndex(_ index: Int) -> (progress: Double, goalMet: Bool, totalMl: Int) {
        let calendar = Calendar.current
        let today = Date()
        guard let targetDate = calendar.date(byAdding: .day, value: index - 6, to: today) else {
            return (0, false, 0)
        }
        let dateString = formatDate(targetDate)
        
        if let data = hydrationService.weeklyData.first(where: { $0.date == dateString }) {
            return (data.progress, data.goalMet, data.totalMl)
        }
        return (0, false, 0)
    }
    
    private func dayLabel(for index: Int) -> String {
        let calendar = Calendar.current
        let today = Date()
        let targetDate = calendar.date(byAdding: .day, value: index - 6, to: today)!

        return String(hydrationDayOfWeekShortFormatter.string(from: targetDate).prefix(1))
    }
    
    private func formatDate(_ date: Date) -> String {
        return hydrationYMDFormatter.string(from: date)
    }
    
    private func formatMl(_ ml: Int) -> String {
        // 2026-05-08 (Bug-intel `6d2dd20f` + `5faa0cc4`): unit-aware
        // formatter. When `usesOz == true`, convert ml → oz (1 oz =
        // ~29.5735 ml) and render in fl oz with 1-decimal precision so
        // small amounts stay legible (e.g. 250 ml → "8.5 oz"). When
        // false, retain the prior ml/L behavior (≥1000 ml → liters).
        if usesOz {
            let oz = Double(ml) / Self.mlPerOz
            // Whole-number oz when within ±0.05 of a round value, else
            // 1-decimal — keeps "8 oz" tidy without losing precision on
            // odd custom amounts.
            if abs(oz - oz.rounded()) < 0.05 {
                return "\(Int(oz.rounded())) oz"
            }
            return String(format: "%.1f oz", oz)
        }
        if ml >= 1000 {
            return String(format: "%.1fL", Double(ml) / 1000.0)
        }
        return "\(ml) ml"
    }

    /// 2026-05-08 (Bug-intel `6d2dd20f` + `5faa0cc4`): card-header oz/ml
    /// segmented toggle. Stays compact (28pt height) so it reads as a
    /// chip rather than a primary action. Tapping a side flips the
    /// shared `hydrationUnitPreference` AppStorage value, which propagates
    /// to AddWaterSheet + DashboardHydrationWidget on the next render.
    @ViewBuilder
    private var unitToggle: some View {
        HStack(spacing: 0) {
            unitToggleButton(label: "oz", active: usesOz) { usesOz = true }
            unitToggleButton(label: "ml", active: !usesOz) { usesOz = false }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hydration units")
        .accessibilityValue(usesOz ? "Ounces" : "Milliliters")
        .accessibilityHint("Double tap to switch units")
    }

    private func unitToggleButton(
        label: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.selectionChanged()
            withAnimation(.easeInOut(duration: 0.15)) {
                action()
            }
        } label: {
            Text(label)
                .font(.ds_caption)
                .fontWeight(active ? .bold : .regular)
                .foregroundColor(active ? .white : .secondary)
                .frame(width: 28, height: 22)
                .background(
                    Group {
                        if active {
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Color.clear
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Water Preset
struct WaterPreset: Identifiable {
    let id = UUID()
    let name: String
    let amountMl: Int
    let icon: String
    
    static let presets: [WaterPreset] = [
        WaterPreset(name: "Glass", amountMl: 250, icon: "drop.fill"),
        WaterPreset(name: "Bottle", amountMl: 500, icon: "waterbottle.fill"),
        WaterPreset(name: "Large", amountMl: 750, icon: "drop.circle.fill"),
        WaterPreset(name: "Small", amountMl: 150, icon: "drop"),
        WaterPreset(name: "XL", amountMl: 1000, icon: "drop.triangle.fill"),
    ]
}

// MARK: - Water Preset Button
struct WaterPresetButton: View {
    let preset: WaterPreset
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.2))
                isPressed = false
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
                Text(preset.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("\(preset.amountMl)ml")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Add Water Sheet
struct AddWaterSheet: View {
    @ObservedObject var hydrationService: HydrationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var customAmount: String = ""
    
    // Unit preference - synced across app
    @AppStorage("hydrationUnitPreference") private var usesOz: Bool = true
    
    private let mlPerOz = 29.5735
    private let gradientColors: [Color] = [.cyan, .blue]
    
    // Quick add amounts
    private let quickAddAmountsOz = [8, 12, 16, 20, 24, 32]
    private let quickAddAmountsMl = [100, 200, 250, 300, 500, 750]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Unit Toggle
                    HStack(spacing: 0) {
                        Button(action: {
                            HapticManager.selectionChanged()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                usesOz = true
                            }
                        }) {
                            Text("oz")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(usesOz ? .white : .secondary)
                                .frame(width: 60, height: 36)
                                .background(
                                    usesOz ? LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(CornerRadius.sm)
                        }
                        
                        Button(action: {
                            HapticManager.selectionChanged()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                usesOz = false
                            }
                        }) {
                            Text("ml")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(!usesOz ? .white : .secondary)
                                .frame(width: 60, height: 36)
                                .background(
                                    !usesOz ? LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(CornerRadius.sm)
                        }
                    }
                    .padding(Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.top, 8)
                    
                    // Custom amount input
                    VStack(spacing: 12) {
                        Text("Custom Amount")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            TextField("Amount", text: $customAmount)
                                .keyboardType(.numberPad)
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .frame(height: 60)
                                .background(Color(.systemGray6))
                                .cornerRadius(CornerRadius.md)
                            
                            Text(usesOz ? "oz" : "ml")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 40)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Quick presets
                    VStack(spacing: 12) {
                        Text("Quick Add")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            if usesOz {
                                ForEach(quickAddAmountsOz, id: \.self) { oz in
                                    Button(action: {
                                        HapticManager.impact(.light)
                                        let ml = Int(Double(oz) * mlPerOz)
                                        Task {
                                            await hydrationService.logWater(amountMl: ml)
                                            dismiss()
                                        }
                                    }) {
                                        Text("\(oz) oz")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(
                                                LinearGradient(
                                                    colors: gradientColors,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .cornerRadius(CornerRadius.md)
                                    }
                                }
                            } else {
                                ForEach(quickAddAmountsMl, id: \.self) { amount in
                                    Button(action: {
                                        HapticManager.impact(.light)
                                        Task {
                                            await hydrationService.logWater(amountMl: amount)
                                            dismiss()
                                        }
                                    }) {
                                        Text("\(amount) ml")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(
                                                LinearGradient(
                                                    colors: gradientColors,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .cornerRadius(CornerRadius.md)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Add Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        guard let amount = Int(customAmount), amount > 0 else { return }
                        // Convert to ml if using oz
                        let ml = usesOz ? Int(Double(amount) * mlPerOz) : amount
                        Task {
                            await hydrationService.logWater(amountMl: ml)
                            dismiss()
                        }
                    }
                    .disabled(customAmount.isEmpty || Int(customAmount) == nil)
                }
            }
        }
    }
}

// MARK: - Water Intake Detail View
struct WaterIntakeDetailView: View {
    @ObservedObject var hydrationService: HydrationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var cardsAppeared = false

    private var expectedProgress: Double {
        let hour = Calendar.current.component(.hour, from: Date())
        let startHour = 8
        let endHour = 22
        if hour < startHour { return 0 }
        if hour >= endHour { return 1.0 }
        return Double(hour - startHour) / Double(endHour - startHour)
    }

    private var paceStatus: (label: String, color: Color, icon: String) {
        let actual = hydrationService.todayProgress
        let expected = expectedProgress
        if expected == 0 { return ("Not Started", .gray, "moon.fill") }
        let ratio = actual / expected
        if ratio >= 1.1 { return ("Ahead", .green, "arrow.up.circle.fill") }
        if ratio >= 0.85 { return ("On Track", .blue, "checkmark.circle.fill") }
        return ("Behind", .orange, "exclamationmark.triangle.fill")
    }

    private var morningLogs: [HydrationLog] {
        hydrationService.todayLogs.filter {
            Calendar.current.component(.hour, from: $0.loggedAt) < 12
        }
    }

    private var afternoonLogs: [HydrationLog] {
        hydrationService.todayLogs.filter {
            let h = Calendar.current.component(.hour, from: $0.loggedAt)
            return h >= 12 && h < 17
        }
    }

    private var eveningLogs: [HydrationLog] {
        hydrationService.todayLogs.filter {
            Calendar.current.component(.hour, from: $0.loggedAt) >= 17
        }
    }

    private var daysGoalMet: Int {
        hydrationService.weeklyData.filter { $0.goalMet }.count
    }

    private var weeklyAverage: Int {
        let data = hydrationService.weeklyData
        guard !data.isEmpty else { return 0 }
        return data.reduce(0) { $0 + $1.totalMl } / data.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        todayProgressCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.05), value: cardsAppeared)

                        paceTrackerCard
                            .padding(.horizontal, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.10), value: cardsAppeared)

                        statsGrid
                            .padding(.horizontal, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.15), value: cardsAppeared)

                        weeklySummaryCard
                            .padding(.horizontal, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.20), value: cardsAppeared)

                        weeklyChart
                            .padding(.horizontal, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.25), value: cardsAppeared)

                        todayLogSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.30), value: cardsAppeared)
                    }
                }
            }
            .navigationTitle("Water Intake")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .accessibilityLabel("Done")
                    .accessibilityHint("Dismiss water intake details")
                }
            }
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    cardsAppeared = true
                }
            }
        }
    }

    // MARK: - Today Progress Card

    private var todayProgressCard: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 20)
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: min(hydrationService.todayProgress, 1.0))
                    .stroke(
                        LinearGradient(
                            colors: hydrationService.todayGoalMet ? [.green, .mint] : [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: hydrationService.todayProgress)

                VStack(spacing: 8) {
                    Text("\(Int(hydrationService.todayProgress * 100))%")
                        .font(.ds_displayMedium)
                        .fontDesign(.rounded)
                        .foregroundColor(.white)

                    Text("\(formatMl(hydrationService.todayTotal)) of \(formatMl(hydrationService.settings.dailyGoalMl))")
                        .font(.ds_labelLarge)
                        .foregroundColor(.gray)

                    if hydrationService.todayGoalMet {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Goal achieved!")
                                .font(.ds_caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        .padding(.top, 4)
                    }
                }
            }

            if let firstTime = hydrationService.todaySummary?.firstDrinkTime,
               let lastTime = hydrationService.todaySummary?.lastDrinkTime {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sunrise.fill")
                        .foregroundColor(.orange)
                        .font(.ds_caption)
                        .accessibilityHidden(true)
                    Text("First: \(formatISOTime(firstTime))")
                        .font(.ds_caption)
                        .foregroundColor(.gray)

                    Text("|")
                        .font(.ds_caption)
                        .foregroundColor(.gray.opacity(0.5))

                    Image(systemName: "sunset.fill")
                        .foregroundColor(.purple)
                        .font(.ds_caption)
                        .accessibilityHidden(true)
                    Text("Last: \(formatISOTime(lastTime))")
                        .font(.ds_caption)
                        .foregroundColor(.gray)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("First drink at \(formatISOTime(firstTime)), last drink at \(formatISOTime(lastTime))")
            }

            HStack {
                Image(systemName: "target")
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
                Text("Goal: \(formatMl(hydrationService.settings.dailyGoalMl))")
                    .font(.ds_labelLarge)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(10)
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }

    // MARK: - Pace Tracker Card

    private var paceTrackerCard: some View {
        let status = paceStatus
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "gauge.medium")
                    .foregroundColor(.cyan)
                    .accessibilityHidden(true)
                Text("Daily Pace")
                    .font(.ds_heading3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: status.icon)
                        .foregroundColor(status.color)
                    Text(status.label)
                        .font(.ds_caption)
                        .fontWeight(.semibold)
                        .foregroundColor(status.color)
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.15))
                .cornerRadius(CornerRadius.sm)
            }

            VStack(spacing: 6) {
                HStack(spacing: Spacing.xs) {
                    Text("Actual")
                        .font(.ds_caption)
                        .foregroundColor(.gray)
                        .frame(width: 60, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * min(hydrationService.todayProgress, 1.0)))
                        }
                    }
                    .frame(height: 10)
                    Text("\(Int(hydrationService.todayProgress * 100))%")
                        .font(.ds_caption)
                        .foregroundColor(.white)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack(spacing: Spacing.xs) {
                    Text("Expected")
                        .font(.ds_caption)
                        .foregroundColor(.gray)
                        .frame(width: 60, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.5))
                                .frame(width: max(4, geo.size.width * expectedProgress))
                        }
                    }
                    .frame(height: 10)
                    Text("\(Int(expectedProgress * 100))%")
                        .font(.ds_caption)
                        .foregroundColor(.gray)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily pace: \(paceStatus.label). Actual \(Int(hydrationService.todayProgress * 100))%, expected \(Int(expectedProgress * 100))%")
    }

    // MARK: - Stats Grid (2×3)

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
            DetailStatBox(
                title: "Current Streak",
                value: "\(hydrationService.streaks?.currentStreak ?? 0)",
                unit: "days",
                icon: "flame.fill",
                color: .orange
            )

            DetailStatBox(
                title: "Best Streak",
                value: "\(hydrationService.streaks?.longestStreak ?? 0)",
                unit: "days",
                icon: "trophy.fill",
                color: .yellow
            )

            DetailStatBox(
                title: "Avg Daily",
                value: formatMlShort(hydrationService.streaks?.avgDailyIntakeMl ?? 0),
                unit: "",
                icon: "chart.line.uptrend.xyaxis",
                color: .blue
            )

            DetailStatBox(
                title: "Total",
                value: String(format: "%.1f", hydrationService.streaks?.totalLitersConsumed ?? 0),
                unit: "liters",
                icon: "drop.fill",
                color: .blue
            )

            DetailStatBox(
                title: "Days Goal Met",
                value: "\(hydrationService.streaks?.totalDaysGoalMet ?? 0)",
                unit: "",
                icon: "checkmark.circle.fill",
                color: .green
            )

            DetailStatBox(
                title: "Best Day",
                value: formatMlShort(hydrationService.streaks?.bestDailyIntakeMl ?? 0),
                unit: "",
                icon: "star.fill",
                color: .yellow
            )
        }
    }

    // MARK: - Weekly Summary Card

    private var weeklySummaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Weekly Summary")
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.white)

            HStack(spacing: 0) {
                weeklySummaryStat(
                    icon: "checkmark.seal.fill",
                    value: "\(daysGoalMet)/7",
                    label: "Days Goal Met",
                    color: .green
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.gray.opacity(0.3))

                weeklySummaryStat(
                    icon: "chart.bar.fill",
                    value: formatMl(weeklyAverage),
                    label: "Avg Intake",
                    color: .cyan
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.gray.opacity(0.3))

                weeklySummaryStat(
                    icon: "star.fill",
                    value: formatMl(hydrationService.streaks?.bestDailyIntakeMl ?? 0),
                    label: bestDayLabel,
                    color: .yellow
                )
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }

    private func weeklySummaryStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.ds_labelLarge)
                .accessibilityHidden(true)
            Text(value)
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var bestDayLabel: String {
        guard let dateStr = hydrationService.streaks?.bestDailyDate else { return "Best Day" }
        guard let date = hydrationYMDFormatter.date(from: dateStr) else { return "Best Day" }
        return hydrationMonthDayFormatter.string(from: date)
    }

    // MARK: - Weekly Chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("This Week")
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.white)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    let dayData = weeklyDataForIndex(index)
                    VStack(spacing: 4) {
                        Text(formatMlShort(dayData.totalMl))
                            .font(.ds_caption)
                            .foregroundColor(.gray)

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 100)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    dayData.goalMet
                                        ? LinearGradient(colors: [.green, .mint], startPoint: .bottom, endPoint: .top)
                                        : LinearGradient(colors: [.cyan, .blue], startPoint: .bottom, endPoint: .top)
                                )
                                .frame(height: max(4, 100 * dayData.progress))
                        }
                        .frame(width: 36)

                        Text(dayLabel(for: index))
                            .font(.ds_caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }

    // MARK: - Today's Log (Grouped by Time Period)

    private var todayLogSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Today's Log")
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if hydrationService.todayLogs.isEmpty {
                Text("No entries yet today")
                    .font(.ds_labelLarge)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                let sortedLogs = hydrationService.todayLogs.sorted { $0.loggedAt < $1.loggedAt }
                VStack(spacing: Spacing.md) {
                    if !morningLogs.isEmpty {
                        logGroup(title: "Morning", icon: "sunrise.fill", color: .orange,
                                 logs: morningLogs, allSorted: sortedLogs)
                    }
                    if !afternoonLogs.isEmpty {
                        logGroup(title: "Afternoon", icon: "sun.max.fill", color: .yellow,
                                 logs: afternoonLogs, allSorted: sortedLogs)
                    }
                    if !eveningLogs.isEmpty {
                        logGroup(title: "Evening", icon: "moon.fill", color: .indigo,
                                 logs: eveningLogs, allSorted: sortedLogs)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }

    @ViewBuilder
    private func logGroup(title: String, icon: String, color: Color,
                          logs: [HydrationLog], allSorted: [HydrationLog]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.ds_caption)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.ds_caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }

            ForEach(logs) { log in
                let running = runningTotalFor(log: log, in: allSorted)
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.blue)
                        .frame(width: 30)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Water")
                            .font(.ds_labelLarge)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Text(formatTime(log.loggedAt))
                            .font(.ds_caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+\(formatMl(log.amountMl))")
                            .font(.ds_labelLarge)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                        Text("Total: \(formatMl(running))")
                            .font(.ds_caption)
                            .foregroundColor(.gray)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(formatMl(log.amountMl)) at \(formatTime(log.loggedAt)), running total \(formatMl(running))")

                if log.id != logs.last?.id {
                    Divider()
                        .background(Color.gray.opacity(0.3))
                }
            }
        }
    }

    // MARK: - Helpers

    private func runningTotalFor(log: HydrationLog, in sortedLogs: [HydrationLog]) -> Int {
        var total = 0
        for entry in sortedLogs {
            total += entry.amountMl
            if entry.id == log.id { break }
        }
        return total
    }

    private func weeklyDataForIndex(_ index: Int) -> (progress: Double, goalMet: Bool, totalMl: Int) {
        let calendar = Calendar.current
        let today = Date()
        guard let targetDate = calendar.date(byAdding: .day, value: index - 6, to: today) else {
            return (0, false, 0)
        }
        let dateString = formatDate(targetDate)

        if let data = hydrationService.weeklyData.first(where: { $0.date == dateString }) {
            return (data.progress, data.goalMet, data.totalMl)
        }
        return (0, false, 0)
    }

    private func dayLabel(for index: Int) -> String {
        let calendar = Calendar.current
        let today = Date()
        guard let targetDate = calendar.date(byAdding: .day, value: index - 6, to: today) else {
            return ""
        }
        return hydrationDayOfWeekFormatter.string(from: targetDate)
    }

    private func formatDate(_ date: Date) -> String {
        return hydrationYMDFormatter.string(from: date)
    }

    private func formatMl(_ ml: Int) -> String {
        if ml >= 1000 {
            return String(format: "%.1fL", Double(ml) / 1000.0)
        }
        return "\(ml)ml"
    }

    private func formatMlShort(_ ml: Int) -> String {
        if ml >= 1000 {
            return String(format: "%.1fL", Double(ml) / 1000.0)
        }
        return "\(ml)"
    }

    private func formatTime(_ date: Date) -> String {
        return hydrationShortTimeFormatter.string(from: date)
    }

    private func formatISOTime(_ isoString: String) -> String {
        guard let date = hydrationISO8601Formatter.date(from: isoString) else { return isoString }
        return hydrationShortTimeFormatter.string(from: date)
    }
}

// MARK: - Hydration Stat Box (for detail view)
struct DetailStatBox: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.ds_heading2)
                .foregroundColor(color)
                .accessibilityHidden(true)

            Text(value)
                .font(.ds_heading2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(unit.isEmpty ? title : unit)
                .font(.ds_caption)
                .foregroundColor(.gray)

            if !unit.isEmpty {
                Text(title)
                    .font(.ds_caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

// MARK: - Goal Celebration Overlay
struct GoalCelebrationOverlay: View {
    @Binding var showCelebration: Bool
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                
                Text("Goal Reached! 💧")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Great job staying hydrated!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(40)
            .background(Color(.systemBackground))
            .cornerRadius(CornerRadius.xl)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
            
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                    scale = 0.8
                }
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                showCelebration = false
            }
        }
    }
}

// MARK: - Water Ring (Styled like Macro Rings)
struct WaterRing: View {
    let progress: Double
    let current: Int
    let goal: Int
    let goalMet: Bool
    
    private let lineWidth: CGFloat = 10
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    Color.blue.opacity(0.2),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            
            // Progress ring
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    LinearGradient(
                        colors: goalMet ? [.green, .mint] : [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: progress)
            
            // Center content
            VStack(spacing: 0) {
                if goalMet {
                    Image(systemName: "checkmark")
                        .font(.ds_heading2)
                        .foregroundColor(.green)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(.ds_statSmall)
                        .foregroundColor(.primary)
                }
            }
            
            // Drop icon at the end of progress
            if progress > 0.05 && progress < 1.0 {
                Circle()
                    .fill(Color.white)
                    .frame(width: lineWidth + 4, height: lineWidth + 4)
                    .overlay(
                        Image(systemName: "drop.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.blue)
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 2)
                    .offset(y: -38)
                    .rotationEffect(.degrees(360 * progress))
            }
        }
    }
}

// MARK: - Week Stat Item
struct WeekStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.ds_bodySmall)
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
        .background(Color(.tertiarySystemBackground).opacity(0.5))
        .cornerRadius(10)
    }
}

// MARK: - Hydration Badge
struct HydrationBadge: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: Spacing.xxxs) {
            Image(systemName: icon)
                .font(.ds_bodySmall)
                .foregroundColor(color)
            
            Text(value)
                .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
            
            Text(title)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Water Goal Info Sheet
struct WaterGoalInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goalMl: Int
    
    // User data for explanation
    private var userWeight: Int {
        let viewContext = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        if let user = try? viewContext.fetch(request).first {
            return Int(user.weight)
        }
        return 0
    }
    
    private var userGoal: String {
        let viewContext = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        if let user = try? viewContext.fetch(request).first {
            return user.fitnessGoal ?? "General Fitness"
        }
        return "General Fitness"
    }
    
    private var baseWater: Int {
        userWeight * 35
    }
    
    private var goalBonus: Int {
        switch userGoal {
        case "Lose Weight", "Weight Loss": return 500
        case "Build Muscle", "Gain Muscle": return 750
        case "Improve Endurance", "Endurance": return 500
        default: return 250
        }
    }
    
    private var goalBonusReason: String {
        switch userGoal {
        case "Lose Weight", "Weight Loss": 
            return "supports metabolism"
        case "Build Muscle", "Gain Muscle": 
            return "aids muscle recovery"
        case "Improve Endurance", "Endurance": 
            return "keeps you hydrated during cardio"
        default: 
            return "maintains activity levels"
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if userWeight > 0 {
                        // Personalized explanation
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Based on your profile:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // Weight calculation
                            HStack {
                                Image(systemName: "scalemass")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                Text("\(userWeight) kg × 35ml = \(formatMl(baseWater))")
                                    .font(.body)
                            }
                            
                            // Goal bonus
                            HStack(alignment: .top) {
                                Image(systemName: "target")
                                    .foregroundColor(.green)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(userGoal): +\(formatMl(goalBonus))")
                                        .font(.body)
                                    Text("(\(goalBonusReason))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(CornerRadius.md)
                        
                        // Total
                        HStack {
                            Text("Your Daily Goal")
                                .font(.headline)
                            Spacer()
                            Text(formatMl(goalMl))
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(
                            LinearGradient(colors: [.blue.opacity(0.15), .blue.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(CornerRadius.md)
                        
                    } else {
                        Text("Your daily water goal is set to help you stay properly hydrated throughout the day.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text("Complete your profile to get a personalized recommendation based on your weight and fitness goals!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    
                    // Tip
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("Drink more on workout days and in hot weather!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(CornerRadius.md)
                }
                .padding()
            }
            .navigationTitle("Your Water Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func formatMl(_ ml: Int) -> String {
        if ml >= 1000 {
            return String(format: "%.1fL", Double(ml) / 1000.0)
        }
        return "\(ml)ml"
    }
}

// MARK: - Preview
#Preview {
    HydrationWidget()
        .padding()
}

