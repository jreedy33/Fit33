import SwiftUI

// MARK: - Smart Program Mini Card

struct SmartProgramMiniCard: View {
    let program: DynamicProgramGenerator.GeneratedProgram
    let onStart: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var programColor: Color {
        switch program.programType {
        case .hypertrophy: return .blue
        case .strength: return .red
        case .fatLoss: return .orange
        case .toning: return .purple
        case .generalFitness: return .green
        case .powerbuilding: return .yellow
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: program.icon)
                    .font(.ds_labelLarge)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(program.splitType.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Name
            Text(program.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Stats
            HStack(spacing: 8) {
                Label("\(program.daysPerWeek)/wk", systemImage: "calendar")
                Label("\(program.durationWeeks)wks", systemImage: "clock")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            
            Spacer()
            
            // Start button
            Button(action: {
                HapticManager.impact(.medium)
                onStart()
            }) {
                Text("Start")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
        }
        .padding(Spacing.sm)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.15)
                        : Color(white: 0.96)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(programColor.opacity(0.3), lineWidth: 1)
        )
    }
}
