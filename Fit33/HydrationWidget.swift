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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row (OUTSIDE the card - matches other sections)
            HStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                
                Text("Hydration")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { HapticManager.selectionChanged(); showingDetailView = true }) {
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 4)
            
            // Card content - swipeable cards matching other carousels
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = 16
                
                HStack(spacing: spacing) {
                    // Card 1: Today's Progress
                    todayCardStyled
                        .frame(width: cardWidth)
                        .opacity(selectedCard == 0 ? 1 : 0)
                    
                    // Card 2: Hydration Insights
                    weeklyTrendsCardStyled
                        .frame(width: cardWidth)
                        .opacity(selectedCard == 1 ? 1 : 0)
                }
                .offset(x: -CGFloat(selectedCard) * (cardWidth + spacing))
            }
            .frame(height: 260)
            .animation(.easeOut(duration: 0.25), value: selectedCard)
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        
                        // Only swipe if horizontal movement is significantly more than vertical
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
            
            // Page indicator dots - OUTSIDE the cards, centered
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
            .padding(.top, 8)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
    
    // MARK: - Today Card (Styled - With Blue Glow)
    private var todayCardStyled: some View {
        todayCard
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - blue colored
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.cyan.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color(white: 0.15), Color(white: 0.10)]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Colored accent border - blue/cyan gradient
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                    Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
    
    // MARK: - Weekly Trends Card (Styled - With Blue Glow)
    private var weeklyTrendsCardStyled: some View {
        weeklyTrendsCard
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - blue colored
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.cyan.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color(white: 0.15), Color(white: 0.10)]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Colored accent border - blue/cyan gradient
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                    Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
    
    // MARK: - Today Card Content (Combined with Weekly)
    private var todayCard: some View {
        VStack(spacing: 12) {
            // Main content - Ring and Stats side by side
            HStack(spacing: 16) {
                // Water Ring
                WaterRing(
                    progress: animateRing ? progress : 0,
                    current: totalMl,
                    goal: goalMl,
                    goalMet: goalMet
                )
                .frame(width: 80, height: 80)
                
                // Stats
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatMl(totalMl))
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("/ \(formatMl(goalMl))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if goalMet {
                        Label("Goal reached!", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("\(formatMl(remainingMl)) remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Add button
                Button(action: { HapticManager.impact(.medium); showingAddSheet = true }) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "plus")
                            .font(.body.bold())
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            // Quick add presets - compact row
            HStack(spacing: 6) {
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
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Divider()
                .padding(.vertical, 2)
            
            // This Week section
            HStack {
                Text("This Week")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(daysMetGoal)/7 days")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            // Compact weekly bar chart
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7) { index in
                    let dayData = weeklyDataForIndex(index)
                    let isToday = index == 6
                    
                    VStack(spacing: 4) {
                        // Bar
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue.opacity(0.12))
                                .frame(height: 50)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    dayData.goalMet
                                        ? LinearGradient(colors: [.green, .mint], startPoint: .bottom, endPoint: .top)
                                        : LinearGradient(colors: [.cyan, .blue.opacity(0.7)], startPoint: .bottom, endPoint: .top)
                                )
                                .frame(height: max(3, 50 * min(dayData.progress, 1.0)))
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Day label
                        Text(dayLabel(for: index))
                            .font(.system(size: 9, weight: isToday ? .bold : .medium))
                            .foregroundColor(isToday ? .blue : .secondary)
                    }
                }
            }
        }
        .padding(14)
    }
    
    // MARK: - Hydration Insights Card (Cool Visual)
    private var weeklyTrendsCard: some View {
        VStack(spacing: 12) {
            // Header with status pill
            HStack {
                Text("Hydration Insights")
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Status pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(hydrationStatusColor)
                        .frame(width: 6, height: 6)
                    Text(hydrationStatus)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(hydrationStatusColor.opacity(0.15))
                .cornerRadius(10)
            }
            
            // Main content row
            HStack(spacing: 14) {
                // Water Drop Visual
                ZStack {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 55))
                        .foregroundColor(.blue.opacity(0.15))
                    
                    Image(systemName: "drop.fill")
                        .font(.system(size: 55))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .bottom, endPoint: .top)
                        )
                        .mask(
                            VStack(spacing: 0) {
                                Rectangle().fill(Color.clear)
                                    .frame(height: 55 * (1 - min(progress, 1.0)))
                                Rectangle().fill(Color.white)
                            }
                        )
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(y: 8)
                }
                .frame(width: 65, height: 70)
                
                // Pace tracker - shows if on track for daily goal
                VStack(alignment: .leading, spacing: 6) {
                    // Expected vs actual
                    let expectedProgress = expectedProgressForTimeOfDay
                    let paceStatus = progress >= expectedProgress ? "On Track" : "Behind"
                    let paceColor: Color = progress >= expectedProgress ? .green : .orange
                    
                    HStack(spacing: 4) {
                        Image(systemName: progress >= expectedProgress ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                            .font(.system(size: 11))
                            .foregroundColor(paceColor)
                        Text(paceStatus)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(paceColor)
                    }
                    
                    // Mini pace bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.2))
                            
                            // Expected marker
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: geo.size.width * min(expectedProgress, 1.0))
                            
                            // Actual progress
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * min(progress, 1.0))
                        }
                    }
                    .frame(height: 6)
                    
                    // Time info
                    Text("Expected: \(Int(expectedProgress * 100))% by now")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Streak & stats column
                VStack(alignment: .trailing, spacing: 4) {
                    if let streak = hydrationService.streaks?.currentStreak, streak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                            Text("\(streak)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        Text("day streak")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "flame")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No streak")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    
                    // Avg comparison
                    let avg = calculateWeeklyAverage()
                    if avg > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: totalMl >= avg ? "arrow.up" : "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                            Text("avg")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(totalMl >= avg ? .green : .orange)
                    }
                }
            }
            
            // Achievement row
            HStack(spacing: 0) {
                HydrationBadge(
                    icon: "trophy.fill",
                    title: "Best Day",
                    value: formatMlShort(bestDayMl),
                    color: .yellow
                )
                
                HydrationBadge(
                    icon: "calendar.badge.checkmark",
                    title: "This Week",
                    value: "\(daysMetGoal)/7",
                    color: .green
                )
                
                HydrationBadge(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Daily Avg",
                    value: formatMlShort(calculateWeeklyAverage()),
                    color: .blue
                )
            }
            
            // Motivational tip with icon
            HStack(spacing: 6) {
                Text(motivationalEmoji)
                    .font(.system(size: 12))
                Text(motivationalText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
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
    
    private func weeklyDataForIndex(_ index: Int) -> (progress: Double, goalMet: Bool) {
        let calendar = Calendar.current
        let today = Date()
        let targetDate = calendar.date(byAdding: .day, value: index - 6, to: today)!
        let dateString = formatDate(targetDate)
        
        if let data = hydrationService.weeklyData.first(where: { $0.date == dateString }) {
            return (data.progress, data.goalMet)
        }
        return (0, false)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
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
        NavigationView {
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
                                .cornerRadius(8)
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
                                .cornerRadius(8)
                        }
                    }
                    .padding(4)
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
                                .cornerRadius(12)
                            
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
                                            .cornerRadius(12)
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
                                            .cornerRadius(12)
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
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background - matches Steps detail
                Color(red: 0.06, green: 0.07, blue: 0.09)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Today's Progress Card
                        todayProgressCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Stats Grid
                        statsGrid
                            .padding(.horizontal, 20)
                        
                        // Weekly Chart
                        weeklyChart
                            .padding(.horizontal, 20)
                        
                        // Today's Log
                        todayLogSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
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
                }
            }
        }
    }
    
    private var todayProgressCard: some View {
        VStack(spacing: 16) {
            // Large progress ring
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 20)
                    .frame(width: 220, height: 220)
                
                // Progress circle
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
                
                // Center content
                VStack(spacing: 8) {
                    Text("\(Int(hydrationService.todayProgress * 100))%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(formatMl(hydrationService.todayTotal)) of \(formatMl(hydrationService.settings.dailyGoalMl))")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    if hydrationService.todayGoalMet {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Goal achieved!")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            
            // Goal display
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.blue)
                Text("Goal: \(formatMl(hydrationService.settings.dailyGoalMl))")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(10)
        }
        .padding(24)
        .background(Color(white: 0.12))
        .cornerRadius(20)
    }
    
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
        }
    }
    
    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Week")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7) { index in
                    let dayData = weeklyDataForIndex(index)
                    VStack(spacing: 4) {
                        Text(formatMlShort(dayData.totalMl))
                            .font(.system(size: 9))
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
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(Color(white: 0.12))
        .cornerRadius(20)
    }
    
    private var todayLogSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Log")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if hydrationService.todayLogs.isEmpty {
                Text("No entries yet today")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(hydrationService.todayLogs) { log in
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Water")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                Text(formatTime(log.loggedAt))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Text("+\(log.amountMl)ml")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                        }
                        
                        if log.id != hydrationService.todayLogs.last?.id {
                            Divider()
                                .background(Color.gray.opacity(0.3))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.12))
        .cornerRadius(20)
    }
    
    // Helpers
    private func weeklyDataForIndex(_ index: Int) -> (progress: Double, goalMet: Bool, totalMl: Int) {
        let calendar = Calendar.current
        let today = Date()
        let targetDate = calendar.date(byAdding: .day, value: index - 6, to: today)!
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
}

// MARK: - Hydration Stat Box (for detail view - no background)
struct DetailStatBox: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(unit.isEmpty ? title : unit)
                .font(.caption)
                .foregroundColor(.gray)
            
            if !unit.isEmpty {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(14)
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
            .cornerRadius(24)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                    scale = 0.8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showCelebration = false
                }
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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
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
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
        VStack(spacing: 6) {
            // Floating icon - no background
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
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
        NavigationView {
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
                        .cornerRadius(12)
                        
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
                        .cornerRadius(12)
                        
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
                    .cornerRadius(12)
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

