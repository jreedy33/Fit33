import SwiftUI

extension DashboardView {
    // MARK: - Dashboard Macros Widget (Quick Access)
    var dashboardMacrosWidget: some View {
        let consumedCalories = mealService.todaysMeals.reduce(0) { $0 + $1.calories }
        let consumedProtein = mealService.todaysMeals.reduce(0) { $0 + $1.protein }
        let consumedFat = mealService.todaysMeals.reduce(0) { $0 + $1.fat }
        
        // Goals (simplified calculation)
        let calorieGoal: Int = {
            guard let user = userManager.currentUser else { return 2200 }
            let weight = user.weight > 0 ? Int(user.weight) : 150
            let height = user.height > 0 ? Int(user.height) : 170
            if weight > 0 && height > 0 {
                let bmr = (10 * Double(weight)) + (6.25 * Double(height)) - 150
                return Int(bmr * 1.55)
            }
            return 2200
        }()
        let proteinGoal = max(100, Int(Double(userManager.currentUser?.weight ?? 150) * 0.8))
        let fatGoal = (calorieGoal * 30 / 100) / 9
        
        // Progress calculations
        let caloriesProgress = calorieGoal > 0 ? min(Double(consumedCalories) / Double(calorieGoal), 1.5) : 0
        let proteinProgress = proteinGoal > 0 ? min(Double(consumedProtein) / Double(proteinGoal), 1.5) : 0
        let fatProgress = fatGoal > 0 ? min(Double(consumedFat) / Double(fatGoal), 1.5) : 0
        let caloriesExceeded = consumedCalories > calorieGoal
        let fatExceeded = consumedFat > fatGoal
        
        return VStack(spacing: 8) {
            // Swipeable cards (Today's Macros + Weekly Progress)
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = 16
                
                HStack(spacing: spacing) {
                    // Card 0: Today's Macros (compact version)
                    compactMacrosCard(
                        consumedCalories: consumedCalories,
                        calorieGoal: calorieGoal,
                        consumedProtein: consumedProtein,
                        proteinGoal: proteinGoal,
                        consumedFat: consumedFat,
                        fatGoal: fatGoal,
                        caloriesProgress: caloriesProgress,
                        proteinProgress: proteinProgress,
                        fatProgress: fatProgress,
                        caloriesExceeded: caloriesExceeded,
                        fatExceeded: fatExceeded
                    )
                    .frame(width: cardWidth)
                    .opacity(selectedMacrosPage == 0 ? 1 : 0)
                    
                    // Card 1: Weekly Progress (compact version)
                    compactWeeklyProgressCard
                        .frame(width: cardWidth)
                        .opacity(selectedMacrosPage == 1 ? 1 : 0)
                }
                .offset(x: -CGFloat(selectedMacrosPage) * (cardWidth + spacing))
            }
            .frame(height: 160)
            .animation(.easeOut(duration: 0.25), value: selectedMacrosPage)
            .simultaneousGesture(
                DragGesture(minimumDistance: 25)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        
                        if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                            HapticManager.impact(.medium)
                            if horizontalAmount < 0 && selectedMacrosPage < 1 {
                                selectedMacrosPage = 1
                            } else if horizontalAmount > 0 && selectedMacrosPage > 0 {
                                selectedMacrosPage = 0
                            }
                        }
                    }
            )
            
            // Page indicators (dash and dot style)
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(selectedMacrosPage == index ? Color.teal : Color.gray.opacity(0.3))
                        .frame(width: selectedMacrosPage == index ? 20 : 8, height: 6)
                        .animation(.easeOut(duration: 0.2), value: selectedMacrosPage)
                        .onTapGesture {
                            HapticManager.impact(.light)
                            selectedMacrosPage = index
                        }
                }
            }
        }
    }
    
    func compactMacrosCard(
        consumedCalories: Int,
        calorieGoal: Int,
        consumedProtein: Int,
        proteinGoal: Int,
        consumedFat: Int,
        fatGoal: Int,
        caloriesProgress: Double,
        proteinProgress: Double,
        fatProgress: Double,
        caloriesExceeded: Bool,
        fatExceeded: Bool
    ) -> some View {
        NavigationLink(value: DashboardRoute.mealPlan) {
            HStack(spacing: 20) {
                // Triple ring (larger to fill space)
                NutritionTripleRing(
                    caloriesProgress: caloriesProgress,
                    proteinProgress: proteinProgress,
                    fatProgress: fatProgress,
                    size: 100,
                    caloriesExceeded: caloriesExceeded,
                    fatExceeded: fatExceeded
                )
                
                // Legend with values
                VStack(alignment: .leading, spacing: 10) {
                    macroLegendRow(name: "Calories", current: consumedCalories, goal: calorieGoal, color: caloriesExceeded ? .red : .teal)
                    macroLegendRow(name: "Protein", current: consumedProtein, goal: proteinGoal, color: .blue)
                    macroLegendRow(name: "Fat", current: consumedFat, goal: fatGoal, color: fatExceeded ? .red : .purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - teal color glow
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                    
                    // Colored accent border (teal)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.teal.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.mint.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: .teal.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func macroLegendRow(name: String, current: Int, goal: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            
            Text(name)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(current)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            +
            Text("/\(goal)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    
    var compactWeeklyProgressCard: some View {
        NavigationLink(value: DashboardRoute.mealPlan) {
            VStack(spacing: 12) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(colors: [.teal, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Weekly Progress")
                        .font(.title3)
                        .fontWeight(.bold)

                    Spacer()
                }
                
                // Simple weekly overview
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { dayOffset in
                        let date = Calendar.current.date(byAdding: .day, value: -6 + dayOffset, to: Date())!
                        let dayName = Calendar.current.shortWeekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
                        let mealsLogged = getMealsForDay(date)
                        let hasData = mealsLogged > 0
                        let isToday = Calendar.current.isDateInToday(date)
                        
                        VStack(spacing: 6) {
                            Text(dayName.prefix(1))
                                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                                .foregroundColor(isToday ? .teal : .secondary)
                            
                            RoundedRectangle(cornerRadius: 5)
                                .fill(hasData 
                                    ? LinearGradient(colors: [.teal, .mint], startPoint: .bottom, endPoint: .top)
                                    : LinearGradient(colors: [Color.gray.opacity(0.2)], startPoint: .bottom, endPoint: .top)
                                )
                                .frame(height: CGFloat(min(mealsLogged * 14 + 10, 70)))
                                .frame(maxHeight: 70, alignment: .bottom)
                            
                            Text("\(mealsLogged)")
                                .font(.ds_caption)
                                .foregroundColor(hasData ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - teal color glow
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                    
                    // Colored accent border (teal)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.teal.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.mint.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: .teal.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func getMealsForDay(_ date: Date) -> Int {
        return mealService.getMealsForDate(date).count
    }
}

/// Isolated wrapper so MealService @Published changes only re-render this widget, not the entire DashboardView
struct DashboardMacrosWrapper: View {
    @ObservedObject private var mealService = MealService.shared
    @EnvironmentObject var userManager: UserManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMacrosPage: Int = 0
    
    var body: some View {
        let consumedCalories = mealService.todaysMeals.reduce(0) { $0 + $1.calories }
        let consumedProtein = mealService.todaysMeals.reduce(0) { $0 + $1.protein }
        let consumedFat = mealService.todaysMeals.reduce(0) { $0 + $1.fat }
        
        let calorieGoal: Int = {
            guard let user = userManager.currentUser else { return 2200 }
            let weight = user.weight > 0 ? Int(user.weight) : 150
            let height = user.height > 0 ? Int(user.height) : 170
            if weight > 0 && height > 0 {
                let bmr = (10 * Double(weight)) + (6.25 * Double(height)) - 150
                return Int(bmr * 1.55)
            }
            return 2200
        }()
        let proteinGoal = max(100, Int(Double(userManager.currentUser?.weight ?? 150) * 0.8))
        let fatGoal = (calorieGoal * 30 / 100) / 9
        
        let caloriesProgress = calorieGoal > 0 ? min(Double(consumedCalories) / Double(calorieGoal), 1.5) : 0
        let proteinProgress = proteinGoal > 0 ? min(Double(consumedProtein) / Double(proteinGoal), 1.5) : 0
        let fatProgress = fatGoal > 0 ? min(Double(consumedFat) / Double(fatGoal), 1.5) : 0
        let caloriesExceeded = consumedCalories > calorieGoal
        let fatExceeded = consumedFat > fatGoal
        
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = 16
                
                HStack(spacing: spacing) {
                    macrosCard(
                        consumedCalories: consumedCalories, calorieGoal: calorieGoal,
                        consumedProtein: consumedProtein, proteinGoal: proteinGoal,
                        consumedFat: consumedFat, fatGoal: fatGoal,
                        caloriesProgress: caloriesProgress, proteinProgress: proteinProgress, fatProgress: fatProgress,
                        caloriesExceeded: caloriesExceeded, fatExceeded: fatExceeded
                    )
                    .frame(width: cardWidth)
                    .opacity(selectedMacrosPage == 0 ? 1 : 0)
                    
                    weeklyCard
                        .frame(width: cardWidth)
                        .opacity(selectedMacrosPage == 1 ? 1 : 0)
                }
                .offset(x: -CGFloat(selectedMacrosPage) * (cardWidth + spacing))
            }
            .frame(height: 160)
            .animation(.easeOut(duration: 0.25), value: selectedMacrosPage)
            .simultaneousGesture(
                DragGesture(minimumDistance: 25)
                    .onEnded { value in
                        let h = value.translation.width
                        let v = abs(value.translation.height)
                        if abs(h) > v * 1.5 && abs(h) > 20 {
                            HapticManager.impact(.medium)
                            if h < 0 && selectedMacrosPage < 1 { selectedMacrosPage = 1 }
                            else if h > 0 && selectedMacrosPage > 0 { selectedMacrosPage = 0 }
                        }
                    }
            )
            
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(selectedMacrosPage == index ? Color.teal : Color.gray.opacity(0.3))
                        .frame(width: selectedMacrosPage == index ? 20 : 8, height: 6)
                        .animation(.easeOut(duration: 0.2), value: selectedMacrosPage)
                        .onTapGesture {
                            HapticManager.impact(.light)
                            selectedMacrosPage = index
                        }
                }
            }
        }
    }
    
    private func macrosCard(
        consumedCalories: Int, calorieGoal: Int,
        consumedProtein: Int, proteinGoal: Int,
        consumedFat: Int, fatGoal: Int,
        caloriesProgress: Double, proteinProgress: Double, fatProgress: Double,
        caloriesExceeded: Bool, fatExceeded: Bool
    ) -> some View {
        NavigationLink(value: DashboardRoute.mealPlan) {
            HStack(spacing: 20) {
                NutritionTripleRing(
                    caloriesProgress: caloriesProgress, proteinProgress: proteinProgress, fatProgress: fatProgress,
                    size: 100, caloriesExceeded: caloriesExceeded, fatExceeded: fatExceeded
                )
                VStack(alignment: .leading, spacing: 10) {
                    macroRow(name: "Calories", current: consumedCalories, goal: calorieGoal, color: caloriesExceeded ? .red : .teal)
                    macroRow(name: "Protein", current: consumedProtein, goal: proteinGoal, color: .blue)
                    macroRow(name: "Fat", current: consumedFat, goal: fatGoal, color: fatExceeded ? .red : .purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.md)
            .background(macrosCardBackground(accent: .teal))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func macroRow(name: String, current: Int, goal: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(name).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text("\(current)").font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
            + Text("/\(goal)").font(.caption).foregroundColor(.secondary)
        }
    }
    
    private var weeklyCard: some View {
        NavigationLink(value: DashboardRoute.mealPlan) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.fill").font(.title3).foregroundStyle(LinearGradient(colors: [.teal, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("Weekly Progress").font(.title3).fontWeight(.bold)
                    Spacer()
                }
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { dayOffset in
                        let date = Calendar.current.date(byAdding: .day, value: -6 + dayOffset, to: Date()) ?? Date()
                        let dayName = Calendar.current.shortWeekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
                        let mealsLogged = mealService.getMealsForDate(date).count
                        let hasData = mealsLogged > 0
                        let isToday = Calendar.current.isDateInToday(date)
                        VStack(spacing: 6) {
                            Text(dayName.prefix(1))
                                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                                .foregroundColor(isToday ? .teal : .secondary)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(hasData
                                    ? LinearGradient(colors: [.teal, .mint], startPoint: .bottom, endPoint: .top)
                                    : LinearGradient(colors: [Color.gray.opacity(0.2)], startPoint: .bottom, endPoint: .top))
                                .frame(height: CGFloat(min(mealsLogged * 14 + 10, 70)))
                                .frame(maxHeight: 70, alignment: .bottom)
                            Text("\(mealsLogged)").font(.ds_caption).foregroundColor(hasData ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
            .padding(Spacing.md)
            .background(macrosCardBackground(accent: .teal))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func macrosCardBackground(accent: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 8).blur(radius: 4)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardBackground)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.mint.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: accent.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
}
