import SwiftUI

struct WorkoutReplayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let insights: [WorkoutInsightCard]
    
    @State private var visibleCards: Set<Int> = []
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    headerSection
                    
                    if insights.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                            insightCard(insight, index: index)
                                .onAppear {
                                    let delay: Double = Double(index) * 0.1
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay)) {
                                        visibleCards.insert(index)
                                    }
                                }
                                .opacity(visibleCards.contains(index) ? 1 : 0)
                                .offset(y: visibleCards.contains(index) ? 0 : 20)
                        }
                    }
                    
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)
            }
            .background(
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
            )
            .navigationTitle("Workout Replay")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .topTrailing) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("Your Workout Replay")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("AI-powered insights from your session")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, Spacing.md)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No Insights Yet")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Complete a few more workouts and we'll have coaching insights for you.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Insight Card
    
    private func insightCard(_ insight: WorkoutInsightCard, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(insight.iconColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: insight.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(insight.iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    priorityBadge(insight.priority)
                    Text(insight.headline)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            
            Text(insight.detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if let tip = insight.actionTip {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                    Text(tip)
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.8))
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.yellow.opacity(colorScheme == .dark ? 0.1 : 0.08))
                )
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
    
    private func priorityBadge(_ priority: ReplayInsightPriority) -> some View {
        let (text, color): (String, Color) = {
            switch priority {
            case .highlight: return ("Highlight", .green)
            case .coaching: return ("Coaching", .blue)
            case .info: return ("Info", .secondary)
            }
        }()
        
        return Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
