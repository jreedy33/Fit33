import SwiftUI

struct WorkoutInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let insights: WorkoutInsights?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated orb background (consistent with other screens)
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let insights = insights {
                            // Header card
                            VStack(spacing: 16) {
                                // Icon
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple, Color.pink],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 60, height: 60)
                                        .shadow(color: .purple.opacity(0.25), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(spacing: 8) {
                                    Text("Workout Breakdown")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("\(insights.exerciseCount) exercises • \(insights.appliedPairings.count) pairing\(insights.appliedPairings.count == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                            
                            // Your Selections card
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 20))
                                    Text("Your Selections")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(insights.userSelections, id: \.self) { selection in
                                        Text(selection)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            .padding(20)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                            
                            // Applied Strategy card
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 20))
                                    Text("Applied Strategy")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                                
                                if insights.appliedPairings.isEmpty {
                                    Text("Random selection based on available exercises and equipment.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                } else {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(Array(insights.appliedPairings.enumerated()), id: \.offset) { index, pairing in
                                            HStack(alignment: .top, spacing: 12) {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color.orange.opacity(0.15))
                                                        .frame(width: 28, height: 28)
                                                    Text("\(index + 1)")
                                                        .font(.caption)
                                                        .fontWeight(.bold)
                                                        .foregroundColor(.orange)
                                                }
                                                
                                                Text(pairing)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(20)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                            
                            // Why This Works card
                            if !insights.pairingDescriptions.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 20))
                                        Text("Why This Works")
                                            .font(.headline)
                                            .fontWeight(.bold)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 16) {
                                        ForEach(Array(insights.pairingDescriptions.enumerated()), id: \.offset) { index, description in
                                            VStack(alignment: .leading, spacing: 6) {
                                                if let colonIndex = description.firstIndex(of: ":") {
                                                    let title = String(description[..<colonIndex])
                                                    let body = String(description[description.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                                                    
                                                    Text(title)
                                                        .font(.subheadline)
                                                        .fontWeight(.bold)
                                                        .foregroundColor(.primary)
                                                    
                                                    Text(body)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                } else {
                                                    Text(description)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                            
                                            if index < insights.pairingDescriptions.count - 1 {
                                                Divider()
                                                    .padding(.vertical, 4)
                                            }
                                        }
                                    }
                                }
                                .padding(20)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                            }
                        } else {
                            // No insights available
                            VStack(spacing: 16) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                
                                Text("No Insights Available")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("This workout was created manually or insights are not available.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(40)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Workout Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

#Preview {
    WorkoutInsightsView(insights: WorkoutInsights(
        userSelections: ["Chest", "Arms"],
        appliedPairings: ["Push Chain (Chest • Shoulders • Triceps)", "Arm Superset (Biceps • Triceps)"],
        pairingDescriptions: [
            "Push Chain (Chest • Shoulders • Triceps): Pairs horizontal and vertical presses so the pecs, anterior delts, and triceps stay warm and share fatigue like a classic push day.",
            "Arm Superset (Biceps • Triceps): Alternating elbow flexion and extension keeps blood moving through the entire upper arm for maximum volume in short time."
        ],
        exerciseCount: 6
    ))
}

