import SwiftUI
import Charts

// MARK: - New Nutrition Components
struct NutritionMetricCard: View {
    let title: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color
    let icon: String
    
    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(current) / Double(goal))
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon and title
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.ds_labelMedium)
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Current value
            VStack(spacing: 2) {
                Text("\(current)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress indicator
            VStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 50 * progress, height: 4)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
                .frame(width: 50)
                
                Text("\(goal) goal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Nutrition Insights Card
struct NutritionInsightsCard: View {
    let insights: [NutritionInsight]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nutrition Insights")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Your daily nutrition analysis")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(insights.indices, id: \.self) { index in
                    WorkingNutritionInsightCard(insight: insights[index])
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
}

struct NutritionInsightCard: View {
    let insight: NutritionInsight
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: insight.icon)
                    .font(.title2)
                    .foregroundColor(insight.color)
                Spacer()
                if let trend = insight.trend {
                    Text(trend)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(insight.color)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(insight.color.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(insight.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .frame(height: 100)
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Macronutrient Pie Chart
struct MacronutrientPieChart: View {
    let macroData: [MacronutrientData]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Macronutrient Breakdown")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Today's calorie distribution")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 24) {
                // Pie Chart
                Chart(macroData) { macro in
                    SectorMark(
                        angle: .value("Calories", macro.calories),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(macro.color)
                }
                .frame(width: 120, height: 120)
                
                // Legend
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(macroData) { macro in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(macro.color)
                                .frame(width: 12, height: 12)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(macro.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("\(Int(macro.value))g • \(Int(macro.calories)) cal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Detailed Nutrition View
struct DetailedNutritionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let macroData: [MacronutrientData]
    let insights: [NutritionInsight]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Detailed Macronutrient Chart
                    MacronutrientPieChart(macroData: macroData)
                    
                    // Detailed Insights
                    NutritionInsightsCard(insights: insights)
                    
                    // Daily Summary Card
                    dailySummaryCard
                    
                    // Weekly Progress Card  
                    weeklyProgressCard
                }
                .padding()
                .padding(.bottom, 60)
            }
            .background(
                AdaptiveGradient.meals(for: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            )
            .navigationTitle("Nutrition Details")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                    .fontWeight(.medium)
                }
            }
        }
    }
    
    private var dailySummaryCard: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Summary")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Today's complete nutrition breakdown")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                SummaryMetricCard(title: "Total Calories", value: "1,920", target: "2,200", color: .red, icon: "flame.fill")
                SummaryMetricCard(title: "Water Intake", value: "6.2L", target: "8L", color: .blue, icon: "drop.fill")
                SummaryMetricCard(title: "Meals Logged", value: "3", target: "4", color: .green, icon: "fork.knife")
                SummaryMetricCard(title: "Nutrition Score", value: "85%", target: "90%", color: .purple, icon: "star.fill")
            }
        }
        .padding(Spacing.lg)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private var weeklyProgressCard: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Progress")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Your nutrition trends this week")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                // These show 0 for new users - data comes from actual meal entries
                ProgressRow(title: "Protein Goals Met", progress: 0.0, color: .blue)
                ProgressRow(title: "Hydration Goals", progress: 0.0, color: .cyan)
                ProgressRow(title: "Whole Foods", progress: 0.0, color: .green)
                ProgressRow(title: "Meal Consistency", progress: 0.0, color: .orange)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct SummaryMetricCard: View {
    let title: String
    let value: String
    let target: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Goal: \(target)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 100)
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct ProgressRow: View {
    let title: String
    let progress: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

// Simple macro progress row for Today's Macros widget
struct MacroProgressRow: View {
    let title: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(current) / Double(goal), 1.0)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(current)\(unit) / \(goal)\(unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

// Insight item for text view
struct InsightItem: Hashable {
    let icon: String
    let text: String
    let color: Color
    
    init(icon: String = "circle.fill", text: String, color: Color) {
        self.icon = icon
        self.text = text
        self.color = color
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
    
    static func == (lhs: InsightItem, rhs: InsightItem) -> Bool {
        lhs.text == rhs.text
    }
}

// Mini Insight Tile for Daily Insights card - floating style (no background)
struct MiniInsightTile: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            // Floating icon
            Image(systemName: icon)
                .font(.ds_heading3).fontWeight(.semibold)
                .foregroundColor(color)
            
            // Value
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            // Title
            Text(title)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Simple legend row for Today's Macros (just text, no progress bar)
struct MacroLegendRow: View {
    let name: String
    let current: Int
    let goal: Int
    let color: Color
    var exceeded: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(name)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            // Show warning icon if exceeded
            if exceeded {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            Text("\(current)g/\(goal)g")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(exceeded ? .red : .secondary)
        }
    }
}

// Weekly progress row showing days completed out of 7
struct WeeklyProgressRow: View {
    let title: String
    let daysCompleted: Int
    let totalDays: Int
    let color: Color
    
    private var progress: Double {
        guard totalDays > 0 else { return 0 }
        return Double(daysCompleted) / Double(totalDays)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(daysCompleted)/\(totalDays) days")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}


// MARK: - Working Nutrition Cards
struct WorkingNutritionInsightCard: View {
    let insight: NutritionInsight
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: insight.icon)
                    .font(.title2)
                    .foregroundColor(insight.color)
                Spacer()
                if let trend = insight.trend {
                    Text(trend)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(insight.color)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(insight.color.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(insight.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

struct WorkingSummaryMetricCard: View {
    let title: String
    let value: String
    let target: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Goal: \(target)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Macro Goals Explainer View (First-time popup)
struct MacroGoalsExplainerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("How Macro Goals Work")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("A quick guide to hitting your nutrition targets")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Rings Visual
                    HStack(spacing: 30) {
                        MacroRingExample(
                            title: "Calories",
                            color: .green,
                            icon: "flame.fill",
                            minPercent: "100%",
                            maxPercent: "115%"
                        )
                        
                        MacroRingExample(
                            title: "Fat",
                            color: .purple,
                            icon: "drop.fill",
                            minPercent: "100%",
                            maxPercent: "120%"
                        )
                    }
                    .padding(.vertical)
                    
                    // Explanation Cards
                    VStack(spacing: 16) {
                        MacroExplainerCard(
                            icon: "checkmark.circle.fill",
                            iconColor: .green,
                            title: "Hit Your Goals",
                            description: "Reach 100% of your calorie and fat targets to complete your rings."
                        )
                        
                        MacroExplainerCard(
                            icon: "arrow.up.circle.fill",
                            iconColor: .orange,
                            title: "Buffer Zone",
                            description: "Life happens! You can go up to 15% over on calories and 20% over on fat and still hit your goal."
                        )
                        
                        MacroExplainerCard(
                            icon: "xmark.circle.fill",
                            iconColor: .red,
                            title: "Excessive Overage",
                            description: "Go beyond the buffer zone and you'll miss your goal for the day. This helps keep you accountable!"
                        )
                        
                        MacroExplainerCard(
                            icon: "leaf.fill",
                            iconColor: .blue,
                            title: "Protein Exception",
                            description: "Protein has no upper limit — more protein supports muscle building and recovery!"
                        )
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Got It!") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Macro Ring Example
struct MacroRingExample: View {
    let title: String
    let color: Color
    let icon: String
    let minPercent: String
    let maxPercent: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                    .frame(width: 70, height: 70)
                
                // Progress ring (showing ~100%)
                Circle()
                    .trim(from: 0, to: 0.85)
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 2) {
                Text("Min: \(minPercent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Max: \(maxPercent)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Macro Explainer Card
struct MacroExplainerCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }
}
