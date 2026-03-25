import SwiftUI
import CoreData

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
            hydrationHeader
            
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = Spacing.md
                
                HStack(spacing: spacing) {
                    todayCard
                        .frame(width: cardWidth, height: 200)
                        .background(hydrationCardBackground)
                        .opacity(selectedCard == 0 ? 1 : 0)
                    
                    weeklyOverviewCard
                        .frame(width: cardWidth, height: 200)
                        .background(hydrationCardBackground)
                        .opacity(selectedCard == 1 ? 1 : 0)
                }
                .offset(x: -CGFloat(selectedCard) * (cardWidth + spacing))
            }
            .frame(height: 200)
            .animation(.easeOut(duration: 0.25), value: selectedCard)
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        
                        if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                            HapticManager.impact(.medium)
                            if horizontalAmount < 0 && selectedCard < 1 {
                                selectedCard = 1
                            } else if horizontalAmount > 0 && selectedCard > 0 {
                                selectedCard = 0
                            }
                        }
                    }
            )
            
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(selectedCard == index ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .scaleEffect(selectedCard == index ? 1.0 : 0.8)
                        .animation(.easeOut(duration: 0.2), value: selectedCard)
                        .onTapGesture {
                            HapticManager.selectionChanged()
                            selectedCard = index
                        }
                }
            }
            .frame(maxWidth: .infinity)
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
    private var hydrationHeader: some View {
        HStack {
            Image(systemName: "drop.fill")
                .font(.ds_heading2)
                .foregroundStyle(
                    LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("Hydration")
                .font(.ds_heading3)
                .foregroundColor(.primary)
            
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
    }
    
    // MARK: - Shared Card Background
    private var hydrationCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.12 : 0.06))
                .offset(y: 6)
                .blur(radius: 4)
            
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .fill(Color.cardBackground)
            
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.08), Color.clear]
                            : [Color.white.opacity(0.8), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(colorScheme == .dark ? 0.35 : 0.2),
                            Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 4)
        .shadow(color: Color.cyan.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Today Card
    private var todayCard: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                WaterRing(
                    progress: animateRing ? progress : 0,
                    current: totalMl,
                    goal: goalMl,
                    goalMet: goalMet
                )
                .frame(width: 64, height: 64)
                
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                        Text(formatMl(totalMl))
                            .font(.ds_statSmall)
                            .foregroundColor(.primary)
                        Text("/ \(formatMl(goalMl))")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if goalMet {
                        Label("Goal reached!", systemImage: "checkmark.circle.fill")
                            .font(.ds_caption)
                            .foregroundColor(.green)
                    } else {
                        Text("\(formatMl(remainingMl)) remaining")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
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
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            
            HStack(spacing: Spacing.xxs) {
                ForEach(WaterPreset.presets.prefix(4)) { preset in
                    Button {
                        HapticManager.impact(.light)
                        Task {
                            let success = await hydrationService.logWater(amountMl: preset.amountMl)
                            if success && hydrationService.todayGoalMet {
                                showCelebration = true
                            }
                        }
                    } label: {
                        Text("\(preset.amountMl)ml")
                            .font(.ds_labelSmall)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(CornerRadius.sm)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.md)
            
            Divider()
                .padding(.horizontal, Spacing.md)
            
            HStack {
                Text("This Week")
                    .font(.ds_caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(daysMetGoal)/7 days")
                    .font(.ds_caption)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, Spacing.md)
            
            HStack(alignment: .bottom, spacing: Spacing.xxs) {
                ForEach(0..<7) { index in
                    let dayData = weeklyDataForIndex(index)
                    let isToday = index == 6
                    
                    VStack(spacing: Spacing.xxxs) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue.opacity(0.1))
                                .frame(height: 44)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    dayData.goalMet
                                        ? LinearGradient(colors: [.green, .mint], startPoint: .bottom, endPoint: .top)
                                        : LinearGradient(colors: [.cyan, .blue.opacity(0.7)], startPoint: .bottom, endPoint: .top)
                                )
                                .frame(height: max(3, 44 * min(dayData.progress, 1.0)))
                        }
                        .frame(maxWidth: .infinity)
                        
                        Text(dayLabel(for: index))
                            .font(.system(size: 9, weight: isToday ? .bold : .medium))
                            .foregroundColor(isToday ? .blue : .secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
            .accessibilityHidden(true)
        }
    }
    
    // MARK: - Weekly Overview Card (Slide 2)
    private var weeklyOverviewCard: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text("Weekly Overview")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: Spacing.xxs) {
                    Circle()
                        .fill(hydrationStatusColor)
                        .frame(width: 5, height: 5)
                    Text(hydrationStatus)
                        .font(.ds_caption)
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxxs)
                .background(hydrationStatusColor.opacity(0.12))
                .cornerRadius(CornerRadius.sm)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            
            HStack(alignment: .bottom, spacing: Spacing.xxs) {
                ForEach(0..<7) { index in
                    let dayData = weeklyDataForIndex(index)
                    let isToday = index == 6
                    
                    VStack(spacing: Spacing.xxxs) {
                        Text(formatMlShort(dayData.totalMl))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(dayData.goalMet ? .green : (isToday ? .cyan : .secondary))
                            .lineLimit(1)
                        
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue.opacity(0.1))
                                .frame(height: 65)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    dayData.goalMet
                                        ? LinearGradient(colors: [.green, .mint], startPoint: .bottom, endPoint: .top)
                                        : LinearGradient(colors: [.cyan, .blue.opacity(0.7)], startPoint: .bottom, endPoint: .top)
                                )
                                .frame(height: max(4, 65 * min(dayData.progress, 1.0)))
                        }
                        .frame(maxWidth: .infinity)
                        
                        Text(dayLabel(for: index))
                            .font(.system(size: 9, weight: isToday ? .bold : .medium))
                            .foregroundColor(isToday ? .blue : .secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .accessibilityHidden(true)
            
            HStack(spacing: 0) {
                HydrationBadge(
                    icon: "flame.fill",
                    title: "Streak",
                    value: "\(hydrationService.streaks?.currentStreak ?? 0)d",
                    color: .orange
                )
                
                HydrationBadge(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Daily Avg",
                    value: formatMlShort(calculateWeeklyAverage()),
                    color: .blue
                )
                
                HydrationBadge(
                    icon: "trophy.fill",
                    title: "Best Day",
                    value: formatMlShort(bestDayMl),
                    color: .yellow
                )
            }
            .padding(.horizontal, Spacing.md)
            .accessibilityElement(children: .combine)
            
            let expectedProgress = expectedProgressForTimeOfDay
            let paceColor: Color = progress >= expectedProgress ? .green : .orange
            
            HStack(spacing: Spacing.xxs) {
                Image(systemName: progress >= expectedProgress ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                    .font(.ds_caption)
                    .foregroundColor(paceColor)
                Text(progress >= expectedProgress ? "On Track" : "Behind")
                    .font(.ds_caption).fontWeight(.semibold)
                    .foregroundColor(paceColor)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: geo.size.width * min(expectedProgress, 1.0))
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(progress, 1.0))
                    }
                }
                .frame(height: 5)
                
                Text("\(Int(progress * 100))%")
                    .font(.ds_caption).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(paceColor)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
    }
    
    // Expected progress based on time of day (8am-10pm active hours)
    private var expectedProgressForTimeOfDay: Double {
        let hour = Calendar.current.component(.hour, from: Date())
        // Assume drinking hours are 8am to 10pm (14 hours)
        let startHour = 8
        let endHour = 22
        
        if hour < startHour { return 0 }
        if hour >= endHour { return 1.0 }
        
        let hoursElapsed = Double(hour - startHour)
        let totalHours = Double(endHour - startHour)
        return hoursElapsed / totalHours
    }
    
    private var motivationalEmoji: String {
        if goalMet { return "🎉" }
        if progress >= 0.75 { return "🔥" }
        
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 10 { return "☀️" }
        if hour < 14 { return "🍽️" }
        if hour < 18 { return "⚡" }
        return "🌙"
    }
    
    private var motivationalText: String {
        if goalMet { return "Goal crushed! Your body thanks you." }
        if progress >= 0.85 { return "Almost there! One more glass!" }
        if progress >= 0.75 { return "Final stretch – finish strong!" }
        
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 10 { return "Start your day right – hydrate!" }
        if hour < 14 { return "Pre-lunch hydration boosts focus." }
        if hour < 18 { return "Afternoon slump? Water helps!" }
        return "Evening catch-up time!"
    }
    
    // Hydration status helpers
    private var hydrationStatus: String {
        switch progress {
        case 0..<0.25: return "Dehydrated"
        case 0.25..<0.5: return "Getting There"
        case 0.5..<0.75: return "Good Progress"
        case 0.75..<1.0: return "Almost There!"
        default: return "Fully Hydrated! 💧"
        }
    }
    
    private var hydrationStatusColor: Color {
        switch progress {
        case 0..<0.25: return .red
        case 0.25..<0.5: return .orange
        case 0.5..<0.75: return .yellow
        case 0.75..<1.0: return .green.opacity(0.7)
        default: return .green
        }
    }
    
    private var motivationalMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        
        if goalMet {
            let celebrations = [
                "🎉 Hydration hero! Your cells are throwing a party!",
                "💧 Water goal crushed! Your skin, brain, and muscles thank you!",
                "🌊 Fully hydrated! Energy and focus: unlocked!",
                "✨ Goal smashed! Proper hydration boosts performance by 20%!",
                "🏆 Water champion! Your body is running at peak efficiency!"
            ]
            return celebrations.randomElement()!
        } else if progress >= 0.85 {
            return "🔥 Almost there! Just \(formatMl(remainingMl)) – one glass away from greatness!"
        } else if progress >= 0.75 {
            let closeMessages = [
                "💪 So close! \(formatMl(remainingMl)) to go – finish what you started!",
                "🎯 Nearly there! A few more sips and you've won the day!",
                "⚡ Final stretch! Your water goal is within reach!"
            ]
            return closeMessages.randomElement()!
        } else if hour < 10 {
            let morningMessages = [
                "☀️ Morning hydration sets the tone! Your body lost water overnight.",
                "🌅 Start strong! A glass of water kickstarts your metabolism.",
                "💧 Morning tip: Water before coffee = better energy all day!"
            ]
            return morningMessages.randomElement()!
        } else if hour >= 12 && hour < 14 && progress < 0.4 {
            return "🍽️ Lunch tip: Drink water before eating – aids digestion and fullness!"
        } else if hour >= 14 && hour < 17 && progress < 0.5 {
            let afternoonMessages = [
                "⚡ Afternoon slump? Dehydration is often the culprit! Drink up!",
                "🧠 Brain fog at 3pm? Your brain is 75% water – refuel it!",
                "💪 Workout later? Start hydrating now for peak performance!"
            ]
            return afternoonMessages.randomElement()!
        } else if hour >= 18 && progress < 0.5 {
            let eveningMessages = [
                "🌙 Evening catch-up time! You've still got hours to hit your goal.",
                "✨ Don't let the day end dry! A few more glasses and you're golden.",
                "🎯 Behind on water? Small sips over the evening adds up fast!"
            ]
            return eveningMessages.randomElement()!
        } else if progress < 0.3 {
            let lowMessages = [
                "💡 Tip: Keep a water bottle visible – out of sight = out of mind!",
                "📱 Set hourly reminders! Building the habit is the hardest part.",
                "🥤 Struggling? Try sparkling water or add lemon for flavor!"
            ]
            return lowMessages.randomElement()!
        } else if progress >= 0.5 && progress < 0.75 {
            let midMessages = [
                "🌊 Halfway there! Keep the momentum flowing!",
                "👏 Good progress! You're building a healthy habit.",
                "💧 Nice work! Consistency is making you healthier every day."
            ]
            return midMessages.randomElement()!
        } else {
            // Weekend-specific
            if dayOfWeek == 1 || dayOfWeek == 7 {
                return "🌴 Weekend hydration matters too! Stay on track."
            }
            return "🌊 Keep it up! Every sip counts toward a healthier you."
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
        
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: targetDate).prefix(1))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func formatMl(_ ml: Int) -> String {
        if ml >= 1000 {
            return String(format: "%.1fL", Double(ml) / 1000.0)
        }
        return "\(ml)ml"
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return "Best Day" }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: targetDate)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatISOTime(_ isoString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        guard let date = isoFormatter.date(from: isoString) else { return isoString }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

