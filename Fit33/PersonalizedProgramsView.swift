//
//  PersonalizedProgramsView.swift
//  GoFit
//
//  Displays 10 personalized training programs with progressive series,
//  lazy day generation, and smart recommendations
//

import SwiftUI

struct PersonalizedProgramsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var programEngine = SmartProgramEngine.shared
    
    @EnvironmentObject var workoutManager: WorkoutManager
    
    @State private var selectedProgram: PersonalizedProgram?
    @State private var showingProgramDetail = false
    @State private var showingActiveProgram = false
    
    private var programs: [PersonalizedProgram] {
        programEngine.getPersonalizedPrograms(for: userManager.currentUser)
    }
    
    private var activeProgram: SmartActiveProgram? {
        programEngine.userPrograms
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }  // Most recent first
            .first
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Active Program Widget (replaces "Best Match" when program is active)
                if let active = activeProgram {
                    activeFullProgramWidget(active)
                }
                // Your Top Match (only shown when NO active program)
                else if let topMatch = programs.first {
                    topMatchSection(topMatch)
                }
                
                // Progressive Series Section
                progressiveSeriesSection
                
                // All Programs Grid
                allProgramsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(backgroundGradient)
        .navigationTitle("Your Programs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProgram) { program in
            ProgramDetailSheet(program: program, onStart: {
                startProgram(program)
            })
            .environmentObject(userManager)
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark
                ? [Color.purple.opacity(0.15), Color.blue.opacity(0.1), Color.black]
                : [Color.purple.opacity(0.2), Color.blue.opacity(0.1), Color.white]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    
    // MARK: - Active Program Full Widget
    
    private func activeFullProgramWidget(_ program: SmartActiveProgram) -> some View {
        // Get template from personalized programs list
        let personalizedProgram = programs.first { $0.template.id == program.templateId }
        let template = personalizedProgram?.template
        let totalDays = template?.totalDays ?? program.generatedDays.count
        let currentWeek = (program.currentDay - 1) / 7 + 1
        let totalWeeks = (totalDays + 6) / 7
        let progressPercent = Double(program.completedDays.count) / Double(totalDays)
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                    Text("Active Program")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                NavigationLink(destination: SmartProgramOverviewView(
                    program: program,
                    template: template
                )
                .environmentObject(workoutManager)
                .environmentObject(userManager)) {
                    Text("View Details")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // Program card
            VStack(spacing: 12) {
                // Top row with icon and info
                HStack(spacing: 12) {
                    // Icon with progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 5)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: progressPercent)
                            .stroke(
                                LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-90))
                        
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green, Color.mint],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(program.personalizedName)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text("Week \(currentWeek) of \(totalWeeks) • \(Int(progressPercent * 100))% complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(program.completedDays.count)/\(totalDays) workouts done")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                }
                
                // Today's workout (if available)
                if let day = currentDay, !day.isCompleted, !day.exercises.isEmpty {
                    Divider()
                    
                    NavigationLink(destination: SmartProgramDayPreviewView(
                        program: program,
                        day: day,
                        programName: program.personalizedName,
                        totalDays: totalDays
                    )
                    .environmentObject(workoutManager)
                    .environmentObject(userManager)) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Today: \(day.name)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 10) {
                                    Label("\(day.exercises.count)", systemImage: "figure.strengthtraining.traditional")
                                    Label("~\(day.targetDuration) min", systemImage: "clock")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("START")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    LinearGradient(
                                        colors: [.green, .mint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(14)
            .background(
                colorScheme == .dark 
                    ? Color(white: 0.15)
                    : Color.white
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.green.opacity(0.4), lineWidth: 2)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, x: 0, y: 5)
            // Prominent green glow for active program
            .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.4 : 0.25), radius: 16, x: 0, y: 0)
            .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 24, x: 0, y: 0)
            .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 32, x: 0, y: 0)
        }
    }
    
    // MARK: - Top Match
    
    private func topMatchSection(_ program: PersonalizedProgram) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("Best Match For You")
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(program.matchPercentage)% Match")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
            }
            
            Button(action: { selectedProgram = program }) {
                TopMatchCard(program: program)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Progressive Series
    
    private var progressiveSeriesSection: some View {
        let progressiveSeries = Dictionary(grouping: programs.filter { $0.template.isProgressive }) { $0.template.seriesId ?? "" }
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Progressive Series")
                .font(.headline)
                .fontWeight(.bold)
            
            Text("Complete one to unlock the next level")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ForEach(Array(progressiveSeries.keys.sorted()), id: \.self) { seriesId in
                if let seriesPrograms = progressiveSeries[seriesId]?.sorted(by: { ($0.template.seriesOrder ?? 0) < ($1.template.seriesOrder ?? 0) }) {
                    ProgressiveSeriesRow(programs: seriesPrograms, onSelect: { program in
                        selectedProgram = program
                    })
                }
            }
        }
    }
    
    // MARK: - All Programs
    
    private var allProgramsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("All Programs")
                .font(.headline)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(programs.filter { !$0.template.isProgressive }) { program in
                    Button(action: { selectedProgram = program }) {
                        ProgramCard(program: program)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func startProgram(_ program: PersonalizedProgram) {
        guard let user = userManager.currentUser else { return }
        
        if let _ = programEngine.startProgram(templateId: program.template.id, for: user) {
            selectedProgram = nil
            showingActiveProgram = true
        }
    }
}

// MARK: - Top Match Card

struct TopMatchCard: View {
    let program: PersonalizedProgram
    @Environment(\.colorScheme) private var colorScheme
    
    private var totalWeeks: Int {
        (program.template.totalDays + 6) / 7
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 12) {
                // Icon with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [program.template.category.color, program.template.category.color.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: program.template.category.color.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: program.template.category.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(program.personalizedName)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(program.template.difficulty.displayName)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(difficultyColor(program.template.difficulty))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(difficultyColor(program.template.difficulty).opacity(0.15))
                            )
                        
                        Text("\(totalWeeks) weeks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            // Description
            Text(program.personalizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            // Stats row
            HStack(spacing: 12) {
                Label("\(program.template.totalDays) days", systemImage: "calendar")
                Label("\(program.template.daysPerWeek)x/week", systemImage: "repeat")
                Label("~\(program.template.estimatedMinutesPerDay) min", systemImage: "clock")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            
            // Equipment tags
            if !program.template.equipmentRequirements.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(program.template.equipmentRequirements.prefix(4), id: \.self) { equipment in
                            Text(equipment)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.gray.opacity(0.15))
                                )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            colorScheme == .dark 
                ? Color(white: 0.15)
                : Color.white
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(program.template.category.color.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
        // Subtle category-colored glow
        .shadow(color: program.template.category.color.opacity(colorScheme == .dark ? 0.25 : 0.15), radius: 12, x: 0, y: 0)
        .shadow(color: program.template.category.color.opacity(colorScheme == .dark ? 0.15 : 0.1), radius: 20, x: 0, y: 0)
    }
    
    private func difficultyColor(_ difficulty: ProgramDifficultyLevel) -> Color {
        switch difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        case .elite: return .purple
        }
    }
}

// MARK: - Progressive Series Row

struct ProgressiveSeriesRow: View {
    let programs: [PersonalizedProgram]
    let onSelect: (PersonalizedProgram) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var seriesColor: Color {
        programs.first?.template.category.color ?? .gray
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Series header
            if let first = programs.first {
                HStack(spacing: 8) {
                    Image(systemName: first.template.category.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(first.template.category.color)
                    
                    Text(first.template.category.rawValue + " Series")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(programs.count) levels")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Horizontal scroll of program cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(programs) { program in
                        Button(action: { onSelect(program) }) {
                            SeriesLevelCard(program: program)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!program.isUnlocked)
                    }
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - colored based on series
                RoundedRectangle(cornerRadius: 18)
                    .fill(seriesColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color(white: 0.14)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 14)
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
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [
                                seriesColor.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                seriesColor.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: seriesColor.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 16, x: 0, y: 8)
    }
}

struct SeriesLevelCard: View {
    let program: PersonalizedProgram
    @Environment(\.colorScheme) private var colorScheme
    
    private var stepNumber: Int {
        program.template.seriesOrder ?? 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with status
            HStack {
                // Level badge
                Text("\(stepNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(
                                program.isCompleted ? Color.green :
                                program.isUnlocked ? program.template.category.color :
                                Color.gray
                            )
                    )
                
                Spacer()
                
                // Status icon
                if program.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                } else if !program.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Level \(stepNumber)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(program.personalizedName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(program.isUnlocked ? .primary : .secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            
            // Stats
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text("\(program.template.totalDays) days")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("~\(program.template.estimatedMinutesPerDay) min")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 140)
        .background(
            colorScheme == .dark 
                ? Color(white: 0.12)
                : Color.white
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    program.isUnlocked ? program.template.category.color.opacity(0.2) : Color.gray.opacity(0.15),
                    lineWidth: 1
                )
        )
        // Border only, no glow on individual level cards
        .opacity(program.isUnlocked ? 1 : 0.6)
    }
}

// MARK: - Program Card

struct ProgramCard: View {
    let program: PersonalizedProgram
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon and status
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [program.template.category.color, program.template.category.color.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: program.template.category.color.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: program.template.category.icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                if program.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
            }
            
            // Program name (fixed space)
            Text(program.personalizedName)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(height: 40, alignment: .top)
            
            // Difficulty badge
            Text(program.template.difficulty.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(difficultyColor(program.template.difficulty))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(difficultyColor(program.template.difficulty).opacity(0.15))
                )
            
            // Stats section
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundColor(program.template.category.color)
                    Text("\(program.template.totalDays) days")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(program.template.category.color)
                    Text("~\(program.template.estimatedMinutesPerDay) min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(height: 180)
        .background(
            colorScheme == .dark 
                ? Color(white: 0.15)
                : Color.white
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(program.template.category.color.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 6, x: 0, y: 3)
        // Subtle category-colored glow
        .shadow(color: program.template.category.color.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 10, x: 0, y: 0)
        .shadow(color: program.template.category.color.opacity(colorScheme == .dark ? 0.12 : 0.08), radius: 16, x: 0, y: 0)
    }
    
    private func difficultyColor(_ difficulty: ProgramDifficultyLevel) -> Color {
        switch difficulty {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        case .elite: return .purple
        }
    }
}

// MARK: - Program Tag

struct ProgramTag: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }
}

// MARK: - Program Detail Sheet

struct ProgramDetailSheet: View {
    let program: PersonalizedProgram
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userManager: UserManager
    
    @State private var dayPreviews: [DayPreview] = []
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header
                    programHeader
                    
                    // Stats Grid
                    statsGrid
                    
                    // Description
                    descriptionSection
                    
                    // Day Schedule Preview
                    dayScheduleSection
                    
                    // Start Button
                    if program.isUnlocked && !program.isCompleted {
                        startButton
                    } else if !program.isUnlocked {
                        lockedMessage
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Color(UIColor.systemBackground))
            .navigationTitle(program.personalizedName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            dayPreviews = SmartProgramEngine.shared.getDayPreviews(for: program.template)
        }
    }
    
    private var programHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [program.template.category.color, program.template.category.color.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                
                Image(systemName: program.template.category.icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(program.template.category.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(program.template.category.color)
                
                Text(program.personalizedName)
                    .font(.title3)
                    .fontWeight(.bold)
                
                HStack(spacing: 8) {
                    ProgramTag(text: program.template.difficulty.displayName, color: .orange)
                    ProgramTag(text: "\(program.matchPercentage)% Match", color: .green)
                }
            }
            
            Spacer()
        }
    }
    
    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ProgramStatItem(icon: "calendar", value: "\(program.template.totalDays)", label: "Days")
            ProgramStatItem(icon: "repeat", value: "\(program.template.daysPerWeek)x", label: "Per Week")
            ProgramStatItem(icon: "clock", value: "\(program.template.estimatedMinutesPerDay)", label: "Min/Day")
        }
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About This Program")
                .font(.headline)
                .fontWeight(.bold)
            
            Text(program.personalizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Target muscles
            if !program.template.targetMuscleGroups.isEmpty {
                HStack {
                    Text("Targets:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(program.template.targetMuscleGroups.joined(separator: ", "))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
    
    private var dayScheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Schedule Preview")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("First 7 days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(dayPreviews.prefix(7)) { day in
                    DayPreviewRow(day: day, color: program.template.category.color)
                }
                
                if dayPreviews.count > 7 {
                    HStack {
                        Spacer()
                        Text("+ \(dayPreviews.count - 7) more days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
    
    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("Start Program")
            }
            .font(.headline)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [program.template.category.color, program.template.category.color.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: program.template.category.color.opacity(0.4), radius: 12, y: 6)
        }
    }
    
    private var lockedMessage: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Program Locked")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let prereq = program.template.prerequisiteId {
                    Text("Complete the previous level to unlock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Supporting Views

struct ProgramStatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.cardBackground)
        .cornerRadius(10)
    }
}

struct DayPreviewRow: View {
    let day: DayPreview
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Day number
            ZStack {
                Circle()
                    .fill(day.isRestDay ? Color.gray.opacity(0.2) : color.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                if day.isRestDay {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                } else {
                    Text("\(day.dayNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                }
            }
            
            // Day info
            VStack(alignment: .leading, spacing: 2) {
                Text(day.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(day.isRestDay ? .secondary : .primary)
                
                if !day.isRestDay {
                    Text(day.focusMuscles.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Duration/Exercises
            if !day.isRestDay {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(day.exerciseCount) exercises")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("~\(day.estimatedMinutes) min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Rest Day")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(day.isRestDay ? Color.gray.opacity(0.05) : color.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        PersonalizedProgramsView()
            .environmentObject(UserManager.shared)
    }
}

