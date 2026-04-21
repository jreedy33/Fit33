import SwiftUI

// MARK: - Program Overview View
/// Comprehensive overview of an active training program with stats, progress, and day calendar

struct SmartProgramOverviewView: View {
    let program: SmartActiveProgram
    let template: SmartProgramTemplate?
    
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingCancelAlert = false
    
    private var completedDays: Int {
        program.completedDays.count
    }
    
    private var totalDays: Int {
        template?.totalDays ?? program.generatedDays.count
    }
    
    private var progressPercent: Double {
        Double(completedDays) / Double(max(totalDays, 1))
    }
    
    private var currentWeek: Int {
        (program.currentDay - 1) / 7 + 1
    }
    
    private var totalWeeks: Int {
        (totalDays + 6) / 7
    }
    
    private let programColor: Color = .green
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Compact Header
                compactHeader
                
                // Quick Stats Cards
                statsGrid
                
                // Week Calendar
                weekCalendarSection
                
                // Progress Timeline
                progressSection
                
                // Upcoming Workouts
                upcomingWorkoutsSection
                
                Spacer(minLength: 30)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [programColor.opacity(0.15), programColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [programColor.opacity(0.2), programColor.opacity(0.08), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SmartProgramDay.self) { day in
            SmartProgramDayPreviewView(
                program: program,
                day: day,
                programName: program.personalizedName,
                totalDays: totalDays
            )
            .environmentObject(workoutManager)
            .environmentObject(userManager)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Program Overview")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showingCancelAlert = true
                    } label: {
                        Label("Cancel Program", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(programColor)
                }
            }
        }
        .alert("Cancel Program", isPresented: $showingCancelAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End Program", role: .destructive) {
                cancelProgram()
            }
        } message: {
            Text("Are you sure you want to cancel this program? Your progress will be lost.")
        }
    }
    
    private func cancelProgram() {
        // Dismiss immediately for snappy UX; the engine handles local + cloud
        // deletion. Previously this removed the program from in-memory state
        // and local UserDefaults only — `loadProgramsFromCloud()` would then
        // re-append it on next launch from the stale `user_programs` row.
        // `SmartProgramEngine.cancelProgram(id:)` now DELETEs the cloud row.
        let programId = program.id
        Task {
            await SmartProgramEngine.shared.cancelProgram(id: programId)
        }
        dismiss()
    }
    
    // MARK: - Compact Header
    
    private var compactHeader: some View {
        HStack(spacing: 14) {
            // Icon and progress ring combined
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 70, height: 70)
                
                Circle()
                    .trim(from: 0, to: progressPercent)
                    .stroke(
                        LinearGradient(colors: [programColor, programColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [programColor, programColor.opacity(0.7)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                }
            }
            
            // Program info
            VStack(alignment: .leading, spacing: 4) {
                Text(program.personalizedName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text("Week \(currentWeek)/\(totalWeeks)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(progressPercent * 100))% complete")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(programColor)
                }
                
                Text("\(completedDays) of \(totalDays) workouts done")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(
                    colorScheme == .dark 
                        ? Color(white: 0.15)
                        : Color.white
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(programColor.opacity(0.2), lineWidth: 1.5)
        )
    }
    
    // MARK: - Stats Grid
    
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ProgramOverviewStatCard(
                icon: "checkmark.circle.fill",
                value: "\(completedDays)",
                label: "Workouts Done",
                color: programColor
            )
            
            ProgramOverviewStatCard(
                icon: "calendar.badge.clock",
                value: "\(totalDays - completedDays)",
                label: "Remaining",
                color: .orange
            )
            
            ProgramOverviewStatCard(
                icon: "flame.fill",
                value: "\(currentWeek)",
                label: "Current Week",
                color: .red
            )
            
            ProgramOverviewStatCard(
                icon: "target",
                value: "\(totalWeeks)",
                label: "Total Weeks",
                color: .blue
            )
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Week Progress")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                // Week progress
                ForEach(1...totalWeeks, id: \.self) { week in
                    WeekProgressRow(
                        week: week,
                        currentWeek: currentWeek,
                        daysInWeek: daysForWeek(week),
                        completedDays: program.completedDays,
                        color: programColor
                    )
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        colorScheme == .dark 
                            ? Color(white: 0.15)
                            : Color.white
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Week Calendar Section
    
    private var weekCalendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This Week")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Week \(currentWeek) of \(totalWeeks)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(daysForWeek(currentWeek), id: \.self) { dayNumber in
                        if let day = program.generatedDays.first(where: { $0.dayNumber == dayNumber }) {
                            DayCard(
                                day: day,
                                isToday: dayNumber == program.currentDay,
                                program: program,
                                color: programColor
                            )
                            .environmentObject(workoutManager)
                            .environmentObject(userManager)
                        }
                    }
                }
                .padding(.horizontal, Spacing.xxs)
            }
        }
    }
    
    // MARK: - Upcoming Workouts
    
    private var upcomingWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming Workouts")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            VStack(spacing: 10) {
                ForEach(upcomingDays.prefix(5), id: \.dayNumber) { day in
                    NavigationLink(value: day) {
                        UpcomingWorkoutRow(
                            day: day,
                            color: programColor
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func daysForWeek(_ week: Int) -> [Int] {
        let startDay = (week - 1) * 7 + 1
        let endDay = min(week * 7, totalDays)
        return Array(startDay...endDay)
    }
    
    private var upcomingDays: [SmartProgramDay] {
        program.generatedDays
            .filter { $0.dayNumber >= program.currentDay && !$0.isCompleted }
            .sorted { $0.dayNumber < $1.dayNumber }
    }
}

// MARK: - Stat Card Component

struct ProgramOverviewStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.ds_labelLarge)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(
                    colorScheme == .dark 
                        ? Color(white: 0.15)
                        : Color.white
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Week Progress Row

struct WeekProgressRow: View {
    let week: Int
    let currentWeek: Int
    let daysInWeek: [Int]
    let completedDays: [Int]
    let color: Color
    
    private var completedCount: Int {
        daysInWeek.filter { completedDays.contains($0) }.count
    }
    
    private var isCurrentWeek: Bool {
        week == currentWeek
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Week indicator
            Text("W\(week)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(isCurrentWeek ? color : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isCurrentWeek ? color.opacity(0.15) : Color.gray.opacity(0.1))
                )
            
            // Day dots
            HStack(spacing: 4) {
                ForEach(daysInWeek, id: \.self) { day in
                    Circle()
                        .fill(completedDays.contains(day) ? color : Color.gray.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
            
            Spacer()
            
            // Completion count
            Text("\(completedCount)/\(daysInWeek.count)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Day Card

struct DayCard: View {
    let day: SmartProgramDay
    let isToday: Bool
    let program: SmartActiveProgram
    let color: Color
    
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationLink(value: day) {
            VStack(spacing: 6) {
                // Day number badge
                Text("\(day.dayNumber)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isToday ? .white : color)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isToday ? color : color.opacity(0.15))
                    )
                
                // Status indicator
                ZStack {
                    Circle()
                        .fill(
                            day.isCompleted ? color.opacity(0.2) :
                            isToday ? color.opacity(0.15) :
                            Color.gray.opacity(0.1)
                        )
                        .frame(width: 40, height: 40)
                    
                    if day.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.ds_labelLarge)
                            .foregroundColor(color)
                    } else if day.exercises.isEmpty {
                        Image(systemName: "moon.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(.gray)
                    } else {
                        Text("\(day.exercises.count)")
                            .font(.ds_bodySmall).fontWeight(.bold)
                            .foregroundColor(isToday ? color : .secondary)
                    }
                }
                
                // Day name
                Text(day.name.split(separator: " ").first.map(String.init) ?? day.name)
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 70)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(
                        colorScheme == .dark 
                            ? Color(white: 0.15)
                            : Color.white
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(
                        isToday ? color.opacity(0.4) : Color.gray.opacity(0.1),
                        lineWidth: isToday ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Upcoming Workout Row

struct UpcomingWorkoutRow: View {
    let day: SmartProgramDay
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            // Day badge
            Text("\(day.dayNumber)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(color)
                )
            
            // Workout info
            VStack(alignment: .leading, spacing: 2) {
                Text(day.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if day.exercises.isEmpty {
                    Text("Rest Day")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Label("\(day.exercises.count)", systemImage: "figure.strengthtraining.traditional")
                        Label("~\(day.targetDuration) min", systemImage: "clock.fill")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(
                    colorScheme == .dark 
                        ? Color(white: 0.15)
                        : Color.white
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    let testDay = SmartProgramDay(
        id: "test",
        dayNumber: 1,
        name: "Push Day A",
        exercises: [
            SmartProgramExercise(id: "1", exerciseName: "Barbell Bench Press", exerciseId: nil, sets: 4, reps: 8, suggestedWeight: 135, restSeconds: 90, notes: nil, isSuperset: false, supersetWith: nil)
        ],
        targetDuration: 45,
        restBetweenSets: 60,
        isCompleted: false
    )
    
    let testProgram = SmartActiveProgram(
        id: "test",
        templateId: "ppl-classic",
        userId: "user",
        personalizedName: "Foundation Builder",
        startDate: Date(),
        currentDay: 1,
        completedDays: [],
        generatedDays: [testDay],
        isCompleted: false,
        completedDate: nil,
        totalVolume: 0,
        averageIntensity: 0,
        consistencyScore: 1.0
    )
    
    NavigationStack {
        SmartProgramOverviewView(program: testProgram, template: nil)
            .environmentObject(WorkoutManager.shared)
            .environmentObject(UserManager.shared)
    }
}

