import SwiftUI

// MARK: - Full View

struct WhatToEatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var engine = ContextualMealEngine.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    contextHeader
                    
                    if let ctx = engine.context {
                        macroGapsCard(ctx)
                    }
                    
                    if engine.suggestions.isEmpty {
                        emptyState
                    } else {
                        ForEach(engine.suggestions) { suggestion in
                            suggestionCard(suggestion)
                        }
                    }
                    
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)
            }
            .background(
                AnimatedOrbBackground.meals(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
            )
            .navigationTitle("What to Eat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { engine.refresh() }
    }
    
    // MARK: - Context Header
    
    private var contextHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("What Should I Eat Right Now?")
                .font(.title3)
                .fontWeight(.bold)
            
            if let ctx = engine.context {
                Text("\(ctx.timeOfDay.label) • \(ctx.caloriesRemaining) cal remaining")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, Spacing.md)
    }
    
    // MARK: - Macro Gaps Card
    
    private func macroGapsCard(_ ctx: MealContext) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text("Today's Progress")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack(spacing: 12) {
                macroBar(label: "Protein", eaten: ctx.proteinEaten, target: ctx.proteinTarget, color: .blue, unit: "g")
                macroBar(label: "Carbs", eaten: ctx.carbsEaten, target: ctx.carbTarget, color: .orange, unit: "g")
                macroBar(label: "Fat", eaten: ctx.fatEaten, target: ctx.fatTarget, color: .purple, unit: "g")
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
    }
    
    private func macroBar(label: String, eaten: Int, target: Int, color: Color, unit: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.15))
                    .frame(width: 30, height: 60)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 30, height: max(4, 60 * CGFloat(min(eaten, target)) / CGFloat(max(1, target))))
            }
            
            Text("\(eaten)/\(target)\(unit)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Suggestion Card
    
    private func suggestionCard(_ suggestion: MealSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: mealIcon(for: suggestion.mealType))
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                macroChip(value: suggestion.calories, label: "cal", color: .green)
                macroChip(value: suggestion.protein, label: "P", color: .blue)
                macroChip(value: suggestion.carbs, label: "C", color: .orange)
                macroChip(value: suggestion.fat, label: "F", color: .purple)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
    
    private func macroChip(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .foregroundColor(color)
    }
    
    private func mealIcon(for type: String) -> String {
        switch type {
        case "breakfast": return "sun.rise.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.fill"
        case "snacks": return "leaf.fill"
        default: return "fork.knife"
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            
            Text("You're On Track")
                .font(.headline)
            
            Text("Your macros look good for today. Keep it up!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Dashboard Compact Card

struct WhatToEatDashboardCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var engine = ContextualMealEngine.shared
    
    @State private var showingFullView = false
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.light)
            showingFullView = true
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    Text("What to Eat Now")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                if let suggestion = engine.suggestions.first {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text(suggestion.reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(suggestion.calories) cal")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                } else if let ctx = engine.context {
                    Text("\(ctx.caloriesRemaining) cal remaining today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
            )
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear { engine.refresh() }
        .sheet(isPresented: $showingFullView) {
            WhatToEatView()
        }
    }
}
