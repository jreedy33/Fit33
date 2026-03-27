import SwiftUI

struct ProgramLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDifficulty: ProgramDifficulty? = nil
    
    private let programs = WorkoutProgramEngine.shared.getAllPrograms()
    
    private var filteredPrograms: [WorkoutProgram] {
        if let difficulty = selectedDifficulty {
            return programs.filter { $0.difficulty == difficulty }
        }
        return programs
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Difficulty Filter
                difficultyFilter
                
                // Programs Grid
                programsGrid
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.2), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all, edges: .all)
        )
        .navigationDestination(for: WorkoutProgram.self) { program in
            ProgramDetailView(program: program)
        }
        .navigationTitle("Workout Programs")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var headerSection: some View {
        HStack(spacing: 14) {
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
                    .frame(width: 50, height: 50)
                    .shadow(color: .purple.opacity(0.2), radius: 4, x: 0, y: 2)
                
                Image(systemName: "calendar.badge.checkmark")
                    .font(.ds_heading2)
                    .foregroundColor(.white)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text("Structured Training Programs")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Choose from expert-designed workout plans ranging from 7 to 90 days. Each program includes detailed daily workouts, progressive overload, and rest days.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
    }
    
    private var difficultyFilter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter by Level")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, Spacing.xxs)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // All button
                    FilterButton(
                        title: "All Programs",
                        isSelected: selectedDifficulty == nil,
                        color: .blue
                    ) {
                        selectedDifficulty = nil
                    }
                    
                    // Difficulty buttons
                    ForEach(ProgramDifficulty.allCases, id: \.self) { difficulty in
                        FilterButton(
                            title: difficulty.rawValue,
                            isSelected: selectedDifficulty == difficulty,
                            color: colorForDifficulty(difficulty)
                        ) {
                            selectedDifficulty = difficulty
                        }
                    }
                }
            }
        }
    }
    
    private var programsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(filteredPrograms) { program in
                NavigationLink(value: program) {
                    ProgramCardContent(program: program)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private func colorForDifficulty(_ difficulty: ProgramDifficulty) -> Color {
        switch difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(isSelected ? color : Color.white)
                        .overlay(
                            Capsule()
                                .stroke(color, lineWidth: 2)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ProgramCardContent: View {
    let program: WorkoutProgram
    
    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // Icon and duration
                HStack {
                    ZStack {
                        Circle()
                            .fill(programColor.opacity(0.15))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: program.icon)
                            .font(.ds_heading2)
                            .foregroundColor(programColor)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(program.duration)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(programColor)
                        Text("days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Name
                Text(program.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .frame(height: 44, alignment: .topLeading)
                
                // Details
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption)
                        Text(program.difficulty.rawValue)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text("\(program.estimatedTimePerWorkout) min")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.caption)
                        Text("\(program.workoutsPerWeek)x/week")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(Spacing.md)
            .frame(height: 220)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(programColor.opacity(0.2), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var programColor: Color {
        switch program.color {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "pink": return .pink
        default: return .blue
        }
    }
}

struct ProgramDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var workoutManager: WorkoutManager
    let program: WorkoutProgram
    @State private var navigateToDay1 = false
    @State private var showingStartConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Compact header with icon and stats inline
                compactHeader
                
                // Description
                descriptionSection
                
                // Benefits
                benefitsSection
                
                // Equipment
                equipmentSection
                
                // Schedule Preview
                schedulePreview
                
                // Start Button
                startButton
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all, edges: .all)
        )
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var compactHeader: some View {
        VStack(spacing: 12) {
            // Icon and preview text
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(color: programColor.opacity(0.2), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: program.icon)
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                }
                
                Text(program.preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Quick stats inline
            HStack(spacing: 12) {
                StatBox(icon: "calendar", value: "\(program.duration)", label: "Days")
                StatBox(icon: "chart.bar", value: program.difficulty.rawValue, label: "Level")
                StatBox(icon: "clock", value: "\(program.estimatedTimePerWorkout)m", label: "Per Day")
            }
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About This Program")
                .font(.headline)
                .fontWeight(.bold)
            
            Text(program.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What You'll Achieve")
                .font(.title3)
                .fontWeight(.bold)
            
            ForEach(program.benefits, id: \.self) { benefit in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(programColor)
                        .font(.title3)
                    
                    Text(benefit)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
    }
    
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equipment Needed")
                .font(.title3)
                .fontWeight(.bold)
            
            FlowLayout(spacing: 8) {
                ForEach(program.equipment, id: \.self) { equipment in
                    Text(equipment)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(programColor)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(programColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
    }
    
    private var schedulePreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Schedule")
                .font(.title3)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(programColor)
                            .frame(width: 12, height: 12)
                        Text("Training Days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(program.workoutsPerWeek)x per week")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Rest Days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                    }
                    
                    Text("\(program.restDays.count) days")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
            
            Text("Your workouts are strategically planned with rest days for optimal recovery and results.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
    }
    
    private var startButton: some View {
        ZStack {
            // Hidden NavigationLink
            NavigationLink(
                destination: WorkoutPreviewView(program: program, day: 1, programColor: programColor)
                    .environmentObject(workoutManager),
                isActive: $navigateToDay1
            ) {
                EmptyView()
            }
            .opacity(0)
            
            // Visible Button
            Button(action: {
                HapticManager.impact(.medium)
                showingStartConfirmation = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                    Text("Start \(program.duration)-Day Program")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [programColor, programColor.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
                .shadow(color: programColor.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(PlainButtonStyle())
            .alert("Start Program?", isPresented: $showingStartConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Start Program") {
                    AppLogger.debug("🔵 START BUTTON CONFIRMED", category: .workout)
                    workoutManager.startProgram(program)
                    AppLogger.info("✅ Started program: \(program.name)", category: .workout)
                    HapticManager.notification(.success)
                    
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.1))
                        guard !Task.isCancelled else { return }
                        navigateToDay1 = true
                    }
                }
            } message: {
                Text("Ready to begin \(program.name)? This \(program.duration)-day program will become your active program.")
            }
        }
    }
    
    private var programColor: Color {
        switch program.color {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "pink": return .pink
        default: return .blue
        }
    }
    
}

struct StatBox: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    ProgramLibraryView()
}

