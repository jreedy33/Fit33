import SwiftUI

// MARK: - Cloud Program Library View

struct CloudProgramLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @ObservedObject private var programService = CloudProgramService.shared
    
    @State private var selectedDifficulty: String? = nil
    @State private var selectedDuration: Int? = nil
    @State private var searchText = ""
    
    private var filteredPrograms: [CloudProgram] {
        var programs = programService.allPrograms
        
        if !searchText.isEmpty {
            programs = programs.filter { program in
                program.name.localizedCaseInsensitiveContains(searchText) ||
                program.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let difficulty = selectedDifficulty {
            programs = programs.filter { $0.difficulty == difficulty }
        }
        
        if let duration = selectedDuration {
            programs = programs.filter { $0.durationDays == duration }
        }
        
        return programs
        }
        
    private var hasActiveFilters: Bool {
        selectedDifficulty != nil || selectedDuration != nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Compact Filter Bar
                filterBar
                
                // Programs Grid
                programsGrid
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .searchable(text: $searchText, prompt: "Search programs...")
        .background(
            AnimatedOrbBackground.exercises(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
        )
        .navigationDestination(for: CloudProgram.self) { program in
            CloudProgramDetailView(programId: program.id)
        }
        .navigationTitle("Programs")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadPrograms()
        }
        .refreshable {
            await loadPrograms()
        }
        .overlay {
            if programService.isLoading && programService.allPrograms.isEmpty {
                loadingOverlay
            }
        }
    }
    
    // MARK: - Compact Filter Bar
    
    private var filterBar: some View {
        VStack(spacing: 14) {
            // Duration chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // All filter
                    ProgramFilterChip(title: "All", isSelected: selectedDuration == nil && selectedDifficulty == nil, color: .blue) {
                        selectedDuration = nil
                        selectedDifficulty = nil
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Duration filters
                    ProgramFilterChip(title: "7 Days", isSelected: selectedDuration == 7, color: .green) {
                        selectedDuration = selectedDuration == 7 ? nil : 7
                    }
                    ProgramFilterChip(title: "14 Days", isSelected: selectedDuration == 14, color: .cyan) {
                        selectedDuration = selectedDuration == 14 ? nil : 14
                    }
                    ProgramFilterChip(title: "30 Days", isSelected: selectedDuration == 30, color: .purple) {
                        selectedDuration = selectedDuration == 30 ? nil : 30
                    }
                    ProgramFilterChip(title: "90 Days", isSelected: selectedDuration == 90, color: .orange) {
                        selectedDuration = selectedDuration == 90 ? nil : 90
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Difficulty filters
                    ProgramFilterChip(title: "Beginner", isSelected: selectedDifficulty == "beginner", color: .green) {
                        selectedDifficulty = selectedDifficulty == "beginner" ? nil : "beginner"
                    }
                    ProgramFilterChip(title: "Intermediate", isSelected: selectedDifficulty == "intermediate", color: .orange) {
                        selectedDifficulty = selectedDifficulty == "intermediate" ? nil : "intermediate"
                    }
                    ProgramFilterChip(title: "Advanced", isSelected: selectedDifficulty == "advanced", color: .red) {
                        selectedDifficulty = selectedDifficulty == "advanced" ? nil : "advanced"
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Results count
            HStack {
                Text("\(filteredPrograms.count) programs available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if hasActiveFilters {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            selectedDuration = nil
                            selectedDifficulty = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                            Text("Clear")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                // Depth shadow
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 4)
                
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03))
                    .offset(y: 3)
                
                // Main card
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                
                // Top highlight
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.1), Color.clear]
                                : [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Accent border
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.25), Color.blue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
    
    // MARK: - Programs Grid
    
    private var programsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            if filteredPrograms.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(filteredPrograms) { program in
                        NavigationLink(value: program) {
                            DepthProgramCard(program: program)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func clearFilters() {
        withAnimation(.spring(response: 0.3)) {
            selectedDifficulty = nil
            selectedDuration = nil
        }
    }
    
    // MARK: - Helper Views
    
    private var loadingOverlay: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 80, height: 80)
                
            ProgressView()
                .scaleEffect(1.5)
                    .tint(.white)
            }
            
            Text("Loading programs...")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.black.opacity(0.9) : Color.white.opacity(0.9))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                
            Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                Text("No Programs Found")
                .font(.headline)
                    .fontWeight(.bold)
                
                Text("Try adjusting your filters or search terms")
                .font(.subheadline)
                .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if hasActiveFilters {
                Button(action: clearFilters) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Filters")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Helper Methods
    
    private func loadPrograms() async {
        await programService.fetchAllPrograms()
        await programService.fetchRecommendedPrograms()
    }
}

// MARK: - Program Filter Chip (Clean, Simple)

struct ProgramFilterChip: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25)) {
                action()
            }
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(
                                    LinearGradient(colors: [color, color.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .shadow(color: color.opacity(0.35), radius: 6, x: 0, y: 3)
                        } else {
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        }
                    }
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Depth Program Card (Matching App Style)

struct DepthProgramCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let program: CloudProgram
    
    private var difficultyColor: Color {
        switch program.difficulty.lowercased() {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon with gradient
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [program.programColor, program.programColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: program.programColor.opacity(0.35), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: program.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Days badge
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(program.durationDays)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(program.programColor)
                    Text("days")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Title
            Text(program.name)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(height: 40, alignment: .topLeading)
            
            Spacer()
            
            // Info row
            HStack(spacing: 6) {
                // Difficulty
                HStack(spacing: 3) {
                    Circle()
                        .fill(difficultyColor)
                        .frame(width: 6, height: 6)
                    Text(program.difficulty.prefix(3).capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
                
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
                
                // Duration
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text("\(program.avgWorkoutDurationMin)m")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                // Rating
                if let rating = program.ratingAvg {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding(14)
        .frame(height: 170)
        .background(
            ZStack {
                // Bottom depth shadow
                RoundedRectangle(cornerRadius: 18)
                    .fill(program.programColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 4)
                
                // Middle shadow
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03))
                    .offset(y: 3)
                
                // Main card
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                
                // Top highlight
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white.opacity(0.8), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [
                                program.programColor.opacity(colorScheme == .dark ? 0.35 : 0.25),
                                program.programColor.opacity(colorScheme == .dark ? 0.15 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
}

// MARK: - Cloud Program Detail View

struct CloudProgramDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @ObservedObject private var programService = CloudProgramService.shared
    
    let programId: String
    
    @State private var program: CloudProgram?
    @State private var isStarting = false
    @State private var showingStartConfirmation = false
    @State private var navigateToDay1 = false
    @State private var showingCustomization = false
    
    private var programColor: Color {
        program?.programColor ?? .blue
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [programColor.opacity(0.2), Color(red: 0.08, green: 0.08, blue: 0.12)]
                    : [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all, edges: .all)
            
            if let program = program {
                ScrollView {
                    VStack(spacing: 20) {
                        // Hero header - centered icon
        VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                                    .frame(width: 80, height: 80)
                                    .shadow(color: programColor.opacity(0.4), radius: 12, x: 0, y: 6)
                    
                    Image(systemName: program.icon)
                                    .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(program.preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 10)
                        
                        // Stats row - capsule pills
                        HStack(spacing: 8) {
                            statPill(icon: "calendar", value: "\(program.durationDays) Days")
                            statPill(icon: "flame.fill", value: program.difficulty.capitalized)
                            statPill(icon: "clock.fill", value: "\(program.avgWorkoutDurationMin)m")
                            statPill(icon: "figure.run", value: "\(program.workoutsPerWeek)x/wk")
                        }
                        .padding(.horizontal, 20)
                        
                        // Description card
        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                .font(.headline)
                .fontWeight(.bold)
                                .foregroundColor(programColor)
            
            Text(program.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)
                        
                        // Benefits card
                        VStack(alignment: .leading, spacing: 12) {
            Text("What You'll Achieve")
                                .font(.headline)
                .fontWeight(.bold)
                                .foregroundColor(programColor)
            
                            VStack(alignment: .leading, spacing: 8) {
            ForEach(program.benefits, id: \.self) { benefit in
                                    HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(programColor)
                                            .font(.subheadline)
                    
                    Text(benefit)
                                            .font(.subheadline)
                        .foregroundColor(.primary)
                }
            }
        }
    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)
    
                        // Equipment card
        VStack(alignment: .leading, spacing: 12) {
                            Text("Equipment")
                                .font(.headline)
                .fontWeight(.bold)
                                .foregroundColor(programColor)
            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(program.equipment, id: \.self) { equipment in
                    Text(equipment)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(programColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(programColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 140)
                    }
                    .padding(.bottom, 100)
                }
                
                // Fixed bottom buttons
                VStack {
                Spacer()
                
                    VStack(spacing: 10) {
                        // Main Start Button
        Button(action: {
            showingStartConfirmation = true
        }) {
            HStack(spacing: 12) {
                if isStarting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.title3)
                    Text("Start \(program.durationDays)-Day Program")
                        .font(.headline)
                        .fontWeight(.bold)
                }
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
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: programColor.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isStarting)
                        
                        // Customize Button
                        Button(action: {
                            showingCustomization = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.subheadline)
                                Text("Customize This Program")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(programColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(colorScheme == .dark ? Color.cardBackground : programColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(programColor.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0), Color(red: 0.08, green: 0.08, blue: 0.12)]
                                : [Color.white.opacity(0), Color.white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 150)
                        .allowsHitTesting(false)
                    )
                }
            }
        }
        .navigationTitle(program?.name ?? "Program")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToDay1) {
            CloudWorkoutPreviewView(dayNumber: 1, programColor: programColor)
                .environmentObject(workoutManager)
        }
        .task {
            await loadProgram()
        }
        .alert("Start Program?", isPresented: $showingStartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start") {
                Task {
                    await startProgram()
                }
            }
        } message: {
            Text("This will replace any active program you currently have.")
        }
        .sheet(isPresented: $showingCustomization) {
            if let program = program {
                ProgramCustomizationView(
                    baseProgram: program,
                    programColor: programColor
                ) { customProgram in
                    Task {
                        await ProgramCustomizationService.shared.saveCustomProgram(customProgram)
                    }
                }
            }
        }
        .overlay {
            if program == nil {
                ProgressView()
            }
        }
    }
    
    // MARK: - Stat Pill (matching SevenDayProgramDetailView)
    
    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(programColor)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(colorScheme == .dark ? Color.cardBackground : Color.white.opacity(0.8))
        .clipShape(Capsule())
    }
    
    // MARK: - Methods
    
    private func loadProgram() async {
        // First check if we have it in allPrograms
        if let cached = programService.allPrograms.first(where: { $0.id == programId }) {
            program = cached
            return
        }
        
        // Otherwise fetch it
        await programService.fetchAllPrograms()
        program = programService.allPrograms.first(where: { $0.id == programId })
    }
    
    private func startProgram() async {
        isStarting = true
        let success = await programService.startProgram(programId)
        isStarting = false
        
        if success {
            // Navigate to Day 1 workout preview
            navigateToDay1 = true
        }
    }
}

#Preview {
    NavigationStack {
        CloudProgramLibraryView()
            .environmentObject(WorkoutManager.shared)
    }
}

