import SwiftUI

// MARK: - Program Explorer View (Main Entry Point)

struct ProgramExplorerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var libraryService = ProgramLibraryService.shared
    
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var selectedProgram: ExtendedProgram?
    @State private var navigateToDetail = false
    
    // Filter states
    @State private var selectedDifficulty: ProgramDifficulty?
    @State private var selectedLocation: ProgramLocation?
    @State private var selectedGoal: ProgramGoal?
    @State private var selectedDuration: ProgramDuration?
    @State private var selectedFrequency: WorkoutFrequency?
    @State private var selectedSplit: TrainingSplit?
    
    private var filteredPrograms: [ExtendedProgram] {
        libraryService.filterPrograms(
            difficulty: selectedDifficulty,
            location: selectedLocation,
            goal: selectedGoal,
            duration: selectedDuration,
            frequency: selectedFrequency,
            split: selectedSplit,
            searchText: searchText
        )
    }
    
    private var recommendedPrograms: [ExtendedProgram] {
        guard let user = userManager.currentUser else { return [] }
        return libraryService.getRecommendedPrograms(
            forExperience: user.experienceLevel ?? "Intermediate",
            goal: user.fitnessGoal ?? "General Fitness",
            availableDays: Int(user.availableDays),
            equipment: user.getEquipment() ?? ["Dumbbells"],
            limit: 5
        )
    }
    
    private var hasActiveFilters: Bool {
        selectedDifficulty != nil || selectedLocation != nil || selectedGoal != nil ||
        selectedDuration != nil || selectedFrequency != nil || selectedSplit != nil
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Header
                headerView
                    .padding(.top, 8)
                
                // Search bar
                searchBar
                
                // Quick filter pills
                quickFilterPills
                
                // Recommended section (only if no filters active)
                if !hasActiveFilters && searchText.isEmpty {
                    recommendedSection
                }
                
                // Results count
                if hasActiveFilters || !searchText.isEmpty {
                    resultsHeader
                }
                
                // Program grid
                programGrid
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 100)
        }
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.15), Color.mint.opacity(0.1), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationBarHidden(true)
        .background(
            NavigationLink(
                destination: selectedProgram.map { ProgramDetailFullView(program: $0) },
                isActive: $navigateToDetail
            ) { EmptyView() }
            .hidden()
        )
        .sheet(isPresented: $showingFilters) {
            AdvancedProgramFiltersView(
                selectedDifficulty: $selectedDifficulty,
                selectedLocation: $selectedLocation,
                selectedGoal: $selectedGoal,
                selectedDuration: $selectedDuration,
                selectedFrequency: $selectedFrequency,
                selectedSplit: $selectedSplit
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Find Your Program")
                    .font(.ds_heading1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("\(libraryService.allPrograms.count) programs available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Filter button
            Button(action: { showingFilters = true }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(Spacing.sm)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                    
                    if hasActiveFilters {
                        Circle()
                            .fill(.green)
                            .frame(width: 12, height: 12)
                            .offset(x: 2, y: -2)
                    }
                }
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search programs...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        )
    }
    
    // MARK: - Quick Filter Pills
    
    private var quickFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Difficulty pills
                ForEach(ProgramDifficulty.allCases, id: \.self) { difficulty in
                    ProgramFilterPill(
                        title: difficulty.rawValue,
                        isSelected: selectedDifficulty == difficulty,
                        color: difficultyColor(difficulty)
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedDifficulty = selectedDifficulty == difficulty ? nil : difficulty
                        }
                    }
                }
                
                Divider()
                    .frame(height: 20)
                
                // Location pills
                ForEach(ProgramLocation.allCases.prefix(3), id: \.self) { location in
                    ProgramFilterPill(
                        title: location.rawValue,
                        icon: location.icon,
                        isSelected: selectedLocation == location,
                        color: .blue
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedLocation = selectedLocation == location ? nil : location
                        }
                    }
                }
                
                Divider()
                    .frame(height: 20)
                
                // Duration pills
                ForEach([ProgramDuration.oneMonth, .twoMonths, .threeMonths], id: \.self) { duration in
                    ProgramFilterPill(
                        title: duration.shortName,
                        isSelected: selectedDuration == duration,
                        color: .purple
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedDuration = selectedDuration == duration ? nil : duration
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.xxs)
        }
    }
    
    // MARK: - Recommended Section
    
    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("Recommended For You")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recommendedPrograms) { program in
                        ProgramRecommendedCard(program: program) {
                            selectedProgram = program
                            navigateToDetail = true
                        }
                    }
                }
                .padding(.horizontal, Spacing.xxs)
            }
        }
    }
    
    // MARK: - Results Header
    
    private var resultsHeader: some View {
        HStack {
            Text("\(filteredPrograms.count) programs found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if hasActiveFilters {
                Button("Clear All") {
                    withAnimation {
                        clearAllFilters()
                    }
                }
                .font(.subheadline)
                .foregroundColor(.green)
            }
        }
    }
    
    // MARK: - Program Grid
    
    private var programGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
        
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(filteredPrograms) { program in
                ProgramTile(program: program) {
                    selectedProgram = program
                    navigateToDetail = true
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func difficultyColor(_ difficulty: ProgramDifficulty) -> Color {
        switch difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
    
    private func clearAllFilters() {
        selectedDifficulty = nil
        selectedLocation = nil
        selectedGoal = nil
        selectedDuration = nil
        selectedFrequency = nil
        selectedSplit = nil
    }
}

// MARK: - Filter Pill Component

struct ProgramFilterPill: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule()
                    .fill(isSelected ? color : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
    }
}

// MARK: - Recommended Program Card (Horizontal Scroll)

struct ProgramRecommendedCard: View {
    let program: ExtendedProgram
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon and badge
                HStack {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: program.gradientSwiftUIColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: program.icon)
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    if program.isFeatured {
                        Text("TOP PICK")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Capsule().fill(.orange))
                    }
                }
                
                // Title
                Text(program.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // Subtitle
                Text(program.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Stats
                HStack(spacing: 12) {
                    Label(program.duration.shortName, systemImage: "calendar")
                    Label("\(program.workoutsPerWeek)/wk", systemImage: "figure.run")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(Spacing.md)
            .frame(width: 200)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Program Tile (Grid Item)

struct ProgramTile: View {
    let program: ExtendedProgram
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                // Gradient header with icon
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(
                            LinearGradient(
                                colors: program.gradientSwiftUIColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 80)
                    
                    Image(systemName: program.icon)
                        .font(.ds_heading1)
                        .foregroundColor(.white.opacity(0.9))
                    
                    // Badges
                    VStack {
                        HStack {
                            if program.isNew {
                                Text("NEW")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.blue))
                            }
                            Spacer()
                            Text(program.difficulty.rawValue)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.3)))
                        }
                        Spacer()
                    }
                    .padding(Spacing.xs)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(program.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                    
                    // Quick stats row
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(program.duration.shortName)
                                .font(.caption2)
                        }
                        
                        HStack(spacing: 3) {
                            Image(systemName: program.location.icon)
                                .font(.caption2)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("\(program.avgWorkoutMinutes)m")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.xxs)
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Program Detail Full View

struct ProgramDetailFullView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var programStartService = ProgramStartService.shared
    
    let program: ExtendedProgram
    
    @State private var navigateToCustomize = false
    @State private var navigateToSchedule = false
    @State private var showingStartConfirmation = false
    @State private var isStarting = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero header
                heroHeader
                
                // Content
                VStack(spacing: 24) {
                    // Quick stats
                    quickStatsRow
                    
                    // Description
                    descriptionSection
                    
                    // Benefits
                    benefitsSection
                    
                    // Equipment
                    equipmentSection
                    
                    // Preview
                    previewSection
                    
                    // Tags
                    tagsSection
                    
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.ds_heading3)
                        .foregroundColor(.primary)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .background(
            Group {
                NavigationLink(
                    destination: CustomizeProgramView(baseProgram: program),
                    isActive: $navigateToCustomize
                ) { EmptyView() }
                
                NavigationLink(
                    destination: ProgramScheduleFullView(program: program)
                        .environmentObject(workoutManager),
                    isActive: $navigateToSchedule
                ) { EmptyView() }
            }
            .hidden()
        )
        .alert("Start Program", isPresented: $showingStartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start") {
                startProgram()
            }
        } message: {
            Text("Ready to begin \(program.name)? This will be your active program.")
        }
    }
    
    private func startProgram() {
        isStarting = true
        
        // Start the program
        programStartService.startProgram(program, workoutManager: workoutManager)
        
        isStarting = false
        
        // Navigate to schedule
        navigateToSchedule = true
    }
    
    // MARK: - Hero Header
    
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            LinearGradient(
                colors: program.gradientSwiftUIColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 220)
            
            // Icon
            VStack {
                Image(systemName: program.icon)
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                if program.isFeatured {
                    Text("FEATURED")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, Spacing.xxs)
                        .background(Capsule().fill(.white.opacity(0.3)))
                }
                
                Text(program.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(program.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(20)
        }
    }
    
    // MARK: - Quick Stats Row
    
    private var quickStatsRow: some View {
        HStack(spacing: 0) {
            StatItem(icon: "calendar", value: "\(program.durationDays)", label: "Days")
            Divider().frame(height: 40)
            StatItem(icon: "figure.run", value: "\(program.workoutsPerWeek)", label: "Per Week")
            Divider().frame(height: 40)
            StatItem(icon: "clock", value: "\(program.avgWorkoutMinutes)", label: "Minutes")
            Divider().frame(height: 40)
            StatItem(icon: program.location.icon, value: program.location.rawValue, label: "Location", isSmall: true)
        }
        .padding(.vertical, Spacing.md)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    
    // MARK: - Description Section
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About This Program")
                .font(.headline)
                .fontWeight(.bold)
            
            Text(program.description)
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Benefits Section
    
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What You'll Get")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(spacing: 10) {
                ForEach(program.benefits, id: \.self) { benefit in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(benefit)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Equipment Section
    
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equipment Needed")
                .font(.headline)
                .fontWeight(.bold)
            
            ProgramFlowLayout(spacing: 8) {
                ForEach(program.equipment, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What To Expect")
                .font(.headline)
                .fontWeight(.bold)
            
            Text(program.preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(program.gradientSwiftUIColors.first?.opacity(0.1) ?? Color.blue.opacity(0.1))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.headline)
                .fontWeight(.bold)
            
            ProgramFlowLayout(spacing: 8) {
                // Goal tags
                ForEach(program.goals, id: \.rawValue) { goal in
                    HStack(spacing: 4) {
                        Image(systemName: goal.icon)
                            .font(.caption2)
                        Text(goal.rawValue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
                }
                
                // Split tag
                Text(program.split.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                
                // Difficulty tag
                Text(program.difficulty.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(difficultyColor.opacity(0.15))
                    .foregroundColor(difficultyColor)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            // Customize button
            Button(action: { navigateToCustomize = true }) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("Customize")
                }
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            // Start button
            Button(action: { showingStartConfirmation = true }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Program")
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: program.gradientSwiftUIColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial)
    }
    
    private var difficultyColor: Color {
        switch program.difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    var isSmall: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.green)
            
            Text(value)
                .font(isSmall ? .caption : .headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Flow Layout (for tags)

struct ProgramFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}

// MARK: - Customize Program View

struct CustomizeProgramView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var programStartService = ProgramStartService.shared
    
    let baseProgram: ExtendedProgram
    
    @State private var selectedDuration: ProgramDuration
    @State private var selectedFrequency: Int
    @State private var selectedLocation: ProgramLocation
    @State private var workoutLength: Int
    @State private var includeDeloadWeeks = true
    @State private var selectedEquipment: Set<String>
    @State private var navigateToSchedule = false
    
    init(baseProgram: ExtendedProgram) {
        self.baseProgram = baseProgram
        _selectedDuration = State(initialValue: baseProgram.duration)
        _selectedFrequency = State(initialValue: baseProgram.workoutsPerWeek)
        _selectedLocation = State(initialValue: baseProgram.location)
        _workoutLength = State(initialValue: baseProgram.avgWorkoutMinutes)
        _selectedEquipment = State(initialValue: Set(baseProgram.equipment))
    }
    
    private let allEquipment = ["Barbell", "Dumbbells", "Cables", "Machines", "Kettlebells", "Bodyweight", "Resistance Bands", "Pull-Up Bar", "Bench", "Power Rack"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Duration selection
                durationSection
                
                // Frequency selection
                frequencySection
                
                // Location selection
                locationSection
                
                // Workout length
                workoutLengthSection
                
                // Equipment selection
                equipmentSection
                
                // Options
                optionsSection
                
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Customize Program")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            createProgramButton
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Customize")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Based on: \(baseProgram.name)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Program Duration")
                .font(.headline)
                .fontWeight(.bold)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ProgramDuration.allCases, id: \.self) { duration in
                        Button(action: { selectedDuration = duration }) {
                            VStack(spacing: 4) {
                                Text(duration.shortName)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Text("\(duration.days) days")
                                    .font(.caption)
                            }
                            .foregroundColor(selectedDuration == duration ? .white : .primary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(selectedDuration == duration ? Color.green : Color(.systemGray5))
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workouts Per Week")
                .font(.headline)
                .fontWeight(.bold)
            
            HStack(spacing: 10) {
                ForEach(2...7, id: \.self) { days in
                    Button(action: { selectedFrequency = days }) {
                        Text("\(days)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(selectedFrequency == days ? .white : .primary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(selectedFrequency == days ? Color.green : Color(.systemGray5))
                            )
                    }
                }
            }
        }
    }
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Location")
                .font(.headline)
                .fontWeight(.bold)
            
            HStack(spacing: 10) {
                ForEach([ProgramLocation.gym, .home, .hybrid], id: \.self) { location in
                    Button(action: { selectedLocation = location }) {
                        VStack(spacing: 8) {
                            Image(systemName: location.icon)
                                .font(.title2)
                            Text(location.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selectedLocation == location ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(selectedLocation == location ? Color.green : Color(.systemGray5))
                        )
                    }
                }
            }
        }
    }
    
    private var workoutLengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workout Length")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(workoutLength) minutes")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .fontWeight(.semibold)
            }
            
            Slider(value: Binding(
                get: { Double(workoutLength) },
                set: { workoutLength = Int($0) }
            ), in: 20...90, step: 5)
            .accentColor(.green)
        }
    }
    
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Equipment")
                .font(.headline)
                .fontWeight(.bold)
            
            ProgramFlowLayout(spacing: 8) {
                ForEach(allEquipment, id: \.self) { equipment in
                    Button(action: {
                        if selectedEquipment.contains(equipment) {
                            selectedEquipment.remove(equipment)
                        } else {
                            selectedEquipment.insert(equipment)
                        }
                    }) {
                        Text(equipment)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(selectedEquipment.contains(equipment) ? .white : .primary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(selectedEquipment.contains(equipment) ? Color.green : Color(.systemGray5))
                            )
                    }
                }
            }
        }
    }
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)
                .fontWeight(.bold)
            
            Toggle("Include Deload Weeks", isOn: $includeDeloadWeeks)
                .tint(.green)
        }
        .padding(Spacing.md)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }
    
    private var createProgramButton: some View {
        Button(action: {
            createAndStartProgram()
        }) {
            HStack {
                Image(systemName: "sparkles")
                Text("Create My Program")
            }
            .font(.headline)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                LinearGradient(
                    colors: [.green, .mint],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial)
        .background(
            NavigationLink(
                destination: ProgramScheduleFullView(program: baseProgram)
                    .environmentObject(workoutManager),
                isActive: $navigateToSchedule
            ) { EmptyView() }
            .hidden()
        )
    }
    
    private func createAndStartProgram() {
        // Create customization
        let customization = ProgramCustomization(
            duration: selectedDuration,
            frequency: selectedFrequency,
            location: selectedLocation,
            workoutLength: workoutLength,
            equipment: selectedEquipment,
            includeDeloadWeeks: includeDeloadWeeks
        )
        
        // Start the customized program
        programStartService.startProgram(baseProgram, customizations: customization, workoutManager: workoutManager)
        
        // Navigate to schedule
        navigateToSchedule = true
    }
}

// MARK: - Advanced Filters View (Sheet)

struct AdvancedProgramFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedDifficulty: ProgramDifficulty?
    @Binding var selectedLocation: ProgramLocation?
    @Binding var selectedGoal: ProgramGoal?
    @Binding var selectedDuration: ProgramDuration?
    @Binding var selectedFrequency: WorkoutFrequency?
    @Binding var selectedSplit: TrainingSplit?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Experience Level
                    filterSection(title: "Experience Level", icon: "chart.bar.fill") {
                        HStack(spacing: 10) {
                            ForEach(ProgramDifficulty.allCases, id: \.self) { difficulty in
                                FilterChip(
                                    title: difficulty.rawValue,
                                    isSelected: selectedDifficulty == difficulty,
                                    color: difficultyColor(difficulty)
                                ) {
                                    selectedDifficulty = selectedDifficulty == difficulty ? nil : difficulty
                                }
                            }
                        }
                    }
                    
                    // Training Location
                    filterSection(title: "Training Location", icon: "location.fill") {
                        ProgramFlowLayout(spacing: 8) {
                            ForEach(ProgramLocation.allCases, id: \.self) { location in
                                FilterChip(
                                    title: location.rawValue,
                                    icon: location.icon,
                                    isSelected: selectedLocation == location,
                                    color: .blue
                                ) {
                                    selectedLocation = selectedLocation == location ? nil : location
                                }
                            }
                        }
                    }
                    
                    // Goal
                    filterSection(title: "Fitness Goal", icon: "target") {
                        ProgramFlowLayout(spacing: 8) {
                            ForEach(ProgramGoal.allCases, id: \.self) { goal in
                                FilterChip(
                                    title: goal.rawValue,
                                    icon: goal.icon,
                                    isSelected: selectedGoal == goal,
                                    color: .green
                                ) {
                                    selectedGoal = selectedGoal == goal ? nil : goal
                                }
                            }
                        }
                    }
                    
                    // Duration
                    filterSection(title: "Program Length", icon: "calendar") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ProgramDuration.allCases, id: \.self) { duration in
                                    FilterChip(
                                        title: "\(duration.days/7)W",
                                        subtitle: duration.rawValue,
                                        isSelected: selectedDuration == duration,
                                        color: .purple
                                    ) {
                                        selectedDuration = selectedDuration == duration ? nil : duration
                                    }
                                }
                            }
                        }
                    }
                    
                    // Frequency
                    filterSection(title: "Workouts Per Week", icon: "figure.run") {
                        HStack(spacing: 8) {
                            ForEach(WorkoutFrequency.allCases, id: \.self) { frequency in
                                Button(action: {
                                    selectedFrequency = selectedFrequency == frequency ? nil : frequency
                                }) {
                                    Text("\(frequency.rawValue)")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(selectedFrequency == frequency ? .white : .primary)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(selectedFrequency == frequency ? Color.orange : Color(.systemGray5))
                                        )
                                }
                            }
                        }
                    }
                    
                    // Training Split
                    filterSection(title: "Training Split", icon: "rectangle.split.3x1") {
                        ProgramFlowLayout(spacing: 8) {
                            ForEach(TrainingSplit.allCases, id: \.self) { split in
                                FilterChip(
                                    title: split.rawValue,
                                    isSelected: selectedSplit == split,
                                    color: .cyan
                                ) {
                                    selectedSplit = selectedSplit == split ? nil : split
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Filter Programs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        clearAllFilters()
                    }
                    .foregroundColor(.red)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                applyButton
            }
        }
    }
    
    // MARK: - Filter Section Builder
    
    @ViewBuilder
    private func filterSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.green)
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Apply Button
    
    private var applyButton: some View {
        Button(action: { dismiss() }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Apply Filters")
            }
            .font(.headline)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                LinearGradient(
                    colors: [.green, .mint],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Helpers
    
    private func difficultyColor(_ difficulty: ProgramDifficulty) -> Color {
        switch difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
    
    private func clearAllFilters() {
        selectedDifficulty = nil
        selectedLocation = nil
        selectedGoal = nil
        selectedDuration = nil
        selectedFrequency = nil
        selectedSplit = nil
    }
}

// MARK: - Filter Chip Component

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    var subtitle: String? = nil
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.caption)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(isSelected ? color : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
    }
}

#Preview {
    NavigationStack {
        ProgramExplorerView()
            .environmentObject(UserManager())
            .environmentObject(WorkoutManager.shared)
    }
}

