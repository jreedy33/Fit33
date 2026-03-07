import SwiftUI
import CoreData
import AVKit

// MARK: - Cloud Program Schedule Navigation Route

struct CloudScheduleDayRoute: Hashable {
    let dayNumber: Int
}

// MARK: - Cloud Program Schedule View

struct CloudProgramScheduleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @ObservedObject private var programService = CloudProgramService.shared
    
    @State private var showingDaySwap = false
    @State private var selectedDayForSwap: Int? = nil
    @State private var showingCancelAlert = false
    
    private var program: FullCloudProgram? {
        programService.activeProgramDetails
    }
    
    private var activeProgress: UserActiveProgram? {
        programService.activeProgram
    }
    
    private var programColor: Color {
        program?.program.programColor ?? .blue
    }
    
    var body: some View {
        Group {
            if let program = program, let progress = activeProgress {
                programContent(program: program, progress: progress)
            } else {
                loadingView
            }
        }
        .navigationTitle(program?.program.name ?? "My Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingDaySwap = true
                    } label: {
                        Label("Swap Days", systemImage: "arrow.left.arrow.right")
                    }
                    
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
                Task {
                    await programService.cancelProgram()
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to cancel this program? Your progress will be lost.")
        }
        .sheet(isPresented: $showingDaySwap) {
            if let program = program {
                DaySwapView(program: program, programColor: programColor)
            }
        }
        .task {
            await programService.loadActiveProgram()
        }
    }
    
    // MARK: - Content Views
    
    private func programContent(program: FullCloudProgram, progress: UserActiveProgram) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Progress header
                progressHeader(program: program, progress: progress)
                
                // Days grid
                daysGridSection(program: program, progress: progress)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [programColor.opacity(0.2), programColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all, edges: .all)
        )
        .onAppear {
            // 🚀 Smart prefetch: Preload videos for current + upcoming days
            VideoStreamingService.shared.prefetchActiveProgramVideos(
                program: program,
                currentDay: progress.currentDay
            )
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your program...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func progressHeader(program: FullCloudProgram, progress: UserActiveProgram) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: programColor.opacity(0.2), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: program.program.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(progress.currentDay) of \(program.program.durationDays)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(programColor)
                    
                    Text("\(progress.completedDays.count) workouts completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 8)
                    
                    let progressWidth = CGFloat(progress.completedDays.count) / CGFloat(program.program.durationDays)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progressWidth, height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress.completedDays.count)
                }
            }
            .frame(height: 8)
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
    
    private func daysGridSection(program: FullCloudProgram, progress: UserActiveProgram) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workout Schedule")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    showingDaySwap = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Swap Days")
                    }
                    .font(.caption)
                    .foregroundColor(programColor)
                }
            }
            .padding(.horizontal, 4)
            
            // Grid layout for day tiles
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(1...program.program.durationDays, id: \.self) { day in
                    let actualDay = programService.getActualDay(day)
                    let dayDetails = program.days.first { $0.day.dayNumber == actualDay }
                    let isRestDay = dayDetails?.day.isRestDay ?? program.program.restDays.contains(actualDay)
                    let isCompleted = progress.completedDays.contains(day)
                    let isUnlocked = day <= progress.currentDay
                    let hasSwap = progress.daySwaps["\(day)"] != nil
                    
                    if isUnlocked && !isRestDay {
                        NavigationLink(value: CloudScheduleDayRoute(dayNumber: day)) {
                            CloudDayTile(
                                day: day,
                                actualDay: actualDay,
                                dayName: dayDetails?.day.name ?? "Workout",
                                isRestDay: isRestDay,
                                isCompleted: isCompleted,
                                isUnlocked: isUnlocked,
                                hasSwap: hasSwap,
                                programColor: programColor
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        CloudDayTile(
                            day: day,
                            actualDay: actualDay,
                            dayName: isRestDay ? "Rest" : (dayDetails?.day.name ?? "Workout"),
                            isRestDay: isRestDay,
                            isCompleted: isCompleted,
                            isUnlocked: isUnlocked,
                            hasSwap: hasSwap,
                            programColor: programColor
                        )
                    }
                }
            }
            .navigationDestination(for: CloudScheduleDayRoute.self) { route in
                CloudWorkoutPreviewView(
                    dayNumber: route.dayNumber,
                    programColor: programColor
                )
                .environmentObject(workoutManager)
            }
        }
    }
}

// MARK: - Cloud Day Tile

struct CloudDayTile: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let day: Int
    let actualDay: Int
    let dayName: String
    let isRestDay: Bool
    let isCompleted: Bool
    let isUnlocked: Bool
    let hasSwap: Bool
    let programColor: Color
    
    var body: some View {
        VStack(spacing: 6) {
            // Day badge
            ZStack {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 50, height: 50)
                
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                } else if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                } else if isRestDay {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    VStack(spacing: 1) {
                        Text("Day")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("\(day)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Swap indicator
                if hasSwap {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                        .background(Circle().fill(.white).frame(width: 14, height: 14))
                        .offset(x: 18, y: -18)
                }
            }
            
            // Day label
            Text(dayName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(isRestDay ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(height: 95)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .opacity(isUnlocked ? 1.0 : 0.6)
    }
    
    private var badgeColor: Color {
        if isCompleted {
            return programColor
        } else if !isUnlocked {
            return Color.gray.opacity(0.3)
        } else if isRestDay {
            return Color.gray.opacity(0.5)
        } else {
            return programColor.opacity(0.85)
        }
    }
    
    private var cardBackgroundColor: Color {
        if isRestDay {
            return Color.gray.opacity(0.05)
        } else if isCompleted {
            return programColor.opacity(0.08)
        } else {
            return Color.cardBackground
        }
    }
    
    private var borderColor: Color {
        if isRestDay {
            return Color.gray.opacity(0.2)
        } else if isCompleted {
            return programColor.opacity(0.4)
        } else if !isUnlocked {
            return Color.gray.opacity(0.2)
        } else {
            return programColor.opacity(0.3)
        }
    }
}

// MARK: - Day Swap View

struct DaySwapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var programService = CloudProgramService.shared
    
    let program: FullCloudProgram
    let programColor: Color
    
    @State private var selectedDay1: Int? = nil
    @State private var selectedDay2: Int? = nil
    @State private var isSwapping = false
    
    private var canSwap: Bool {
        guard let day1 = selectedDay1, let day2 = selectedDay2 else { return false }
        return day1 != day2
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Instructions
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.largeTitle)
                        .foregroundColor(programColor)
                    
                    Text("Swap Workout Days")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Select two days to swap their workouts. This lets you customize your schedule while keeping the program structure.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                // Selection
                HStack(spacing: 20) {
                    DaySelectionBox(
                        title: "First Day",
                        selectedDay: selectedDay1,
                        dayName: getDayName(selectedDay1),
                        color: programColor
                    )
                    
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    DaySelectionBox(
                        title: "Second Day",
                        selectedDay: selectedDay2,
                        dayName: getDayName(selectedDay2),
                        color: programColor
                    )
                }
                .padding(.horizontal)
                
                // Day picker
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(1...program.program.durationDays, id: \.self) { day in
                            let isRestDay = program.program.restDays.contains(day)
                            
                            Button {
                                selectDay(day)
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(day)")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                    
                                    if let dayDetails = program.days.first(where: { $0.day.dayNumber == day }) {
                                        Text(dayDetails.day.name)
                                            .font(.system(size: 8))
                                            .lineLimit(1)
                                    } else if isRestDay {
                                        Text("Rest")
                                            .font(.system(size: 8))
                                    }
                                }
                                .frame(width: 60, height: 60)
                                .foregroundColor(dayForegroundColor(day, isRestDay: isRestDay))
                                .background(dayBackgroundColor(day, isRestDay: isRestDay))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(dayBorderColor(day), lineWidth: 2)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isRestDay)
                            .opacity(isRestDay ? 0.5 : 1)
                        }
                    }
                    .padding()
                }
                
                // Swap button
                Button {
                    performSwap()
                } label: {
                    HStack {
                        if isSwapping {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Swap Days")
                        }
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(canSwap ? programColor : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                }
                .disabled(!canSwap || isSwapping)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Swap Days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func selectDay(_ day: Int) {
        if selectedDay1 == day {
            selectedDay1 = nil
        } else if selectedDay2 == day {
            selectedDay2 = nil
        } else if selectedDay1 == nil {
            selectedDay1 = day
        } else if selectedDay2 == nil {
            selectedDay2 = day
        } else {
            // Both selected, replace first
            selectedDay1 = day
            selectedDay2 = nil
        }
    }
    
    private func getDayName(_ day: Int?) -> String? {
        guard let day = day else { return nil }
        return program.days.first { $0.day.dayNumber == day }?.day.name
    }
    
    private func dayForegroundColor(_ day: Int, isRestDay: Bool) -> Color {
        if selectedDay1 == day || selectedDay2 == day {
            return .white
        }
        return isRestDay ? .secondary : .primary
    }
    
    private func dayBackgroundColor(_ day: Int, isRestDay: Bool) -> Color {
        if selectedDay1 == day || selectedDay2 == day {
            return programColor
        }
        return isRestDay ? Color.gray.opacity(0.1) : Color.cardBackground
    }
    
    private func dayBorderColor(_ day: Int) -> Color {
        if selectedDay1 == day || selectedDay2 == day {
            return programColor
        }
        return Color.gray.opacity(0.2)
    }
    
    private func performSwap() {
        guard let day1 = selectedDay1, let day2 = selectedDay2 else { return }
        
        isSwapping = true
        
        Task {
            await programService.swapDays(originalDay: day1, newDay: day2)
            isSwapping = false
            dismiss()
        }
    }
}

// MARK: - Day Selection Box

struct DaySelectionBox: View {
    let title: String
    let selectedDay: Int?
    let dayName: String?
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let day = selectedDay {
                VStack(spacing: 4) {
                    Text("Day \(day)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                    
                    if let name = dayName {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Select")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 120, height: 80)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }
}

// MARK: - Cloud Workout Preview View

struct CloudWorkoutPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @ObservedObject private var programService = CloudProgramService.shared
    
    let dayNumber: Int
    let programColor: Color
    
    @State private var generatedExercises: [ExerciseData] = []
    @State private var isGenerating = true
    @State private var showingExerciseSwap = false
    @State private var selectedExerciseIndex: Int? = nil
    @State private var dayDetails: FullProgramDay? = nil
    @State private var loadAttempts = 0
    @State private var selectedExerciseForDetail: ExerciseData? = nil
    @State private var navigateToExerciseDetail = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [programColor.opacity(0.2), programColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if isGenerating {
                loadingView
            } else if generatedExercises.isEmpty {
                emptyStateView
            } else {
                exerciseList
            }
        }
        .navigationTitle("Day \(dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDayAndGenerateExercises()
        }
        .sheet(isPresented: $showingExerciseSwap) {
            if let index = selectedExerciseIndex, index < generatedExercises.count {
                ExerciseSwapView(
                    currentExercise: generatedExercises[index],
                    programColor: programColor
                ) { newExercise in
                    generatedExercises[index] = newExercise
                    // Update the cache with the swapped exercise
                    programService.updateCachedExercise(at: index, with: newExercise, for: dayNumber)
                }
            }
        }
        .navigationDestination(isPresented: $navigateToExerciseDetail) {
            if let exercise = selectedExerciseForDetail {
                ExerciseDataDetailView(exerciseData: exercise)
            }
        }
        .onAppear {
            // Show GO button when exercises are ready
            if !generatedExercises.isEmpty {
                GoButtonState.shared.show(
                    primaryColor: programColor,
                    secondaryColor: programColor.opacity(0.7)
                ) { [self] in
                    startWorkout()
                }
            }
        }
        .onChange(of: isGenerating) { _, stillGenerating in
            if !stillGenerating && !generatedExercises.isEmpty {
                GoButtonState.shared.show(
                    primaryColor: programColor,
                    secondaryColor: programColor.opacity(0.7)
                ) { [self] in
                    startWorkout()
                }
            }
        }
        .onDisappear {
            GoButtonState.shared.hide()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(programColor)
            
            Text("Generating your workout...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Couldn't load exercises")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Please go back and try again")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Retry") {
                Task {
                    await loadDayAndGenerateExercises()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(programColor)
        }
        .padding()
    }
    
    private var exerciseList: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                if let day = dayDetails {
                    dayHeader(day)
                }
                
                // Exercise list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today's Exercises")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.caption2)
                            Text("to swap")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    VStack(spacing: 10) {
                        ForEach(Array(generatedExercises.enumerated()), id: \.offset) { index, exercise in
                            SwappableExerciseCardWithActions(
                                number: index + 1,
                                exercise: exercise,
                                programColor: programColor,
                                onTapCard: {
                                    selectedExerciseForDetail = exercise
                                    navigateToExerciseDetail = true
                                },
                                onTapSwap: {
                                    selectedExerciseIndex = index
                                    showingExerciseSwap = true
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }
    
    private func dayHeader(_ day: FullProgramDay) -> some View {
        HStack(spacing: 14) {
            // Day badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                
                VStack(spacing: 0) {
                    Text("Day")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("\(dayNumber)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(day.day.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 11))
                        Text("\(generatedExercises.count) exercises")
                            .font(.caption2)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                        Text(day.day.intensity.capitalized)
                            .font(.caption2)
                    }
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(14)
        .background(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 3)
    }
    
    private func loadDayAndGenerateExercises() async {
        // Check if we already have cached exercises for this day
        if let cachedExercises = programService.getCachedExercises(for: dayNumber), !cachedExercises.isEmpty {
            print("📦 Using cached exercises for day \(dayNumber) - \(cachedExercises.count) exercises")
            generatedExercises = cachedExercises
            
            // Still load day details for the header
            if programService.activeProgramDetails == nil {
                await programService.loadActiveProgram()
            }
            dayDetails = programService.getDayDetails(for: dayNumber)
            isGenerating = false
            return
        }
        
        isGenerating = true
        print("🏃 loadDayAndGenerateExercises started for day \(dayNumber)")
        
        // Wait for activeProgramDetails to load (retry up to 15 times)
        for attempt in 1...15 {
            print("   Attempt \(attempt): checking activeProgramDetails...")
            if programService.activeProgramDetails != nil {
                print("   ✅ activeProgramDetails is available!")
                break
            }
            print("   activeProgramDetails is nil, loading...")
            await programService.loadActiveProgram()
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Debug: check what we have
        print("   Final check - activeProgramDetails: \(programService.activeProgramDetails != nil ? "exists" : "nil")")
        print("   Final check - days count: \(programService.activeProgramDetails?.days.count ?? 0)")
        
        // Get day details
        dayDetails = programService.getDayDetails(for: dayNumber)
        
        guard let day = dayDetails else {
            print("⚠️ Could not load day \(dayNumber) details")
            print("   Available days: \(programService.activeProgramDetails?.days.map { $0.day.dayNumber } ?? [])")
            isGenerating = false
            return
        }
        
        print("📋 Generating exercises for Day \(dayNumber): \(day.day.name)")
        print("   Focus areas: \(day.day.focusAreas)")
        print("   Exercise count: \(day.day.exerciseCount)")
        print("   Predefined exercises: \(day.exercises.count)")
        
        // Generate exercises
        generatedExercises = programService.generateExercisesForDay(day)
        
        // Cache the generated exercises so they don't change
        programService.cacheExercises(generatedExercises, for: dayNumber)
        
        print("✅ Generated and cached \(generatedExercises.count) exercises")
        isGenerating = false
    }
    
    private func startWorkout() {
        guard let day = dayDetails else { return }
        
        // Create workout
        let workout = Workout(context: viewContext)
        workout.id = UUID()
        workout.name = day.day.name
        workout.date = Date()
        workout.duration = 0
        workout.isCompleted = false
        
        // Convert to Core Data exercises
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let exercises = generatedExercises.compactMap { exerciseData in
            allExercises.first { $0.name == exerciseData.name }
        }
        
        // Start workout
        workoutManager.startWorkout(
            workout: workout,
            exercises: exercises,
            insights: nil,
            programDay: dayNumber,
            programDayFocus: day.day.name
        )
    }
}

// MARK: - Swappable Exercise Card

struct SwappableExerciseCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let number: Int
    let exercise: ExerciseData
    let programColor: Color
    
    private var categoryColor: Color {
        switch exercise.category.lowercased() {
        case "chest": return .purple
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "neck": return .indigo
        default: return .cyan
        }
    }
    
    private var categoryGradient: [Color] {
        switch exercise.category.lowercased() {
        case "chest": return [Color.purple, Color.pink]
        case "back": return [Color.blue, Color.cyan]
        case "legs": return [Color.green, Color.teal]
        case "shoulders": return [Color.orange, Color.yellow]
        case "arms": return [Color.purple, Color.indigo]
        case "core": return [Color.yellow, Color.orange]
        case "full body": return [Color.pink, Color.red]
        default: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
    
    private var categoryIcon: String {
        let exerciseName = exercise.name.lowercased()
        
        if exerciseName.contains("dumbbell") {
            return "dumbbell.fill"
        } else if exerciseName.contains("barbell") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("cable") {
            return "dot.radiowaves.left.and.right"
        } else if exerciseName.contains("squat") {
            return "figure.squat"
        } else if exerciseName.contains("press") {
            return "arrow.up.circle.fill"
        } else if exerciseName.contains("curl") {
            return "figure.arms.open"
        } else if exerciseName.contains("row") {
            return "arrow.left.and.right.circle.fill"
        }
        
        switch exercise.category.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.climbing"
        case "legs": return "figure.squat"
        case "shoulders": return "arrow.up.circle.fill"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Compact exercise icon with vibrant gradient (matching exercise library)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: categoryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: categoryGradient[0].opacity(0.25), radius: 4, x: 0, y: 2)
                
                Image(systemName: categoryIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(exercise.category)
                        .font(.caption)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(exercise.equipment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron (matching exercise library style)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored (subtle)
                RoundedRectangle(cornerRadius: 28)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: [
                                categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
        .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Swappable Exercise Card With Actions

struct SwappableExerciseCardWithActions: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let number: Int
    let exercise: ExerciseData
    let programColor: Color
    let onTapCard: () -> Void
    let onTapSwap: () -> Void
    
    private var categoryColor: Color {
        switch exercise.category.lowercased() {
        case "chest": return .purple
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "neck": return .indigo
        default: return .cyan
        }
    }
    
    private var categoryGradient: [Color] {
        switch exercise.category.lowercased() {
        case "chest": return [Color.purple, Color.pink]
        case "back": return [Color.blue, Color.cyan]
        case "legs": return [Color.green, Color.teal]
        case "shoulders": return [Color.orange, Color.yellow]
        case "arms": return [Color.purple, Color.indigo]
        case "core": return [Color.yellow, Color.orange]
        case "full body": return [Color.pink, Color.red]
        default: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
    
    private var categoryIcon: String {
        let exerciseName = exercise.name.lowercased()
        
        if exerciseName.contains("dumbbell") {
            return "dumbbell.fill"
        } else if exerciseName.contains("barbell") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("cable") {
            return "dot.radiowaves.left.and.right"
        } else if exerciseName.contains("squat") {
            return "figure.squat"
        } else if exerciseName.contains("press") {
            return "arrow.up.circle.fill"
        } else if exerciseName.contains("curl") {
            return "figure.arms.open"
        } else if exerciseName.contains("row") {
            return "arrow.left.and.right.circle.fill"
        }
        
        switch exercise.category.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.climbing"
        case "legs": return "figure.squat"
        case "shoulders": return "arrow.up.circle.fill"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Tappable card area (opens detail sheet)
            Button(action: onTapCard) {
                HStack(spacing: 12) {
                    // Compact exercise icon with vibrant gradient (matching exercise library)
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: categoryGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(color: categoryGradient[0].opacity(0.25), radius: 4, x: 0, y: 2)
                        
                        Image(systemName: categoryIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    // Exercise details
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            Text(exercise.category)
                                .font(.caption)
                                .foregroundColor(categoryColor)
                                .fontWeight(.medium)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text(exercise.equipment)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Info indicator
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Swap button (separate tap target)
            Button(action: onTapSwap) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(categoryColor)
                    .padding(Spacing.xs)
                    .background(
                        Circle()
                            .fill(categoryColor.opacity(0.1))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored (subtle)
                RoundedRectangle(cornerRadius: 28)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: [
                                categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
        .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Exercise Data Detail Sheet (Card/Sheet version with video)

struct ExerciseDataDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var videoManager = VideoPlayerManager()
    
    let exerciseData: ExerciseData
    
    private var categoryColor: Color {
        switch exerciseData.category.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .pink
        case "neck": return .indigo
        default: return .cyan
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Video Section
                    videoSection
                    
                    // Content Section
                    VStack(alignment: .leading, spacing: 20) {
                        // Exercise Name & Category Badge
                        VStack(alignment: .leading, spacing: 12) {
                            Text(exerciseData.name)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 12) {
                                // Category Badge
                                HStack(spacing: 6) {
                                    Image(systemName: categoryIcon)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(exerciseData.category)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        colors: [categoryColor, categoryColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(20)
                                
                                // Equipment Badge
                                HStack(spacing: 6) {
                                    Image(systemName: "dumbbell.fill")
                                        .font(.system(size: 12))
                                    Text(exerciseData.equipment)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .cornerRadius(20)
                            }
                        }
                        .padding(.top, 16)
                        
                        // Primary Muscle
                        sectionCard(title: "Primary Muscle", icon: "figure.strengthtraining.traditional") {
                            muscleTag(exerciseData.primaryMuscle, isPrimary: true)
                        }
                        
                        // Secondary Muscles
                        if !exerciseData.secondaryMuscles.isEmpty {
                            sectionCard(title: "Secondary Muscles", icon: "figure.arms.open") {
                                FlowLayout(spacing: 8) {
                                    ForEach(exerciseData.secondaryMuscles, id: \.self) { muscle in
                                        muscleTag(muscle, isPrimary: false)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        
                        // How to Perform
                        if let steps = extractSteps(from: exerciseData.instructions) {
                            sectionCard(title: "How to Perform", icon: "list.number") {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                        stepRow(number: index + 1, text: step)
                                    }
                                }
                            }
                        } else if !exerciseData.instructions.isEmpty {
                            sectionCard(title: "Instructions", icon: "text.alignleft") {
                                Text(exerciseData.instructions)
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(4)
                            }
                        }
                        
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Exercise Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(categoryColor)
                }
            }
        }
    }
    
    // MARK: - Video Section
    
    private var videoSection: some View {
        ZStack {
            if let videoURL = getVideoURL(for: exerciseData.name) {
                VideoPlayer(player: videoManager.player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .onAppear {
                        videoManager.setupPlayer(with: videoURL)
                    }
                    .onDisappear {
                        videoManager.pause()
                    }
            } else {
                // Fallback illustration
                ZStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [categoryColor.opacity(0.3), categoryColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 60))
                            .foregroundColor(categoryColor)
                        
                        Text("Video Coming Soon")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }
        }
    }
    
    // MARK: - Section Card
    
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(categoryColor)
                
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            content()
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(.systemGray6).opacity(0.5) : Color(.systemGray6).opacity(0.5))
        )
    }
    
    // MARK: - Muscle Tag
    
    private func muscleTag(_ muscle: String, isPrimary: Bool) -> some View {
        Text(muscle)
            .font(.system(size: 14, weight: isPrimary ? .bold : .semibold))
            .foregroundColor(isPrimary ? .white : categoryColor)
            .padding(.horizontal, 14)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPrimary ? categoryColor : categoryColor.opacity(0.15))
            )
    }
    
    // MARK: - Step Row
    
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 26, height: 26)
                
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(categoryColor)
            }
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Helper Properties
    
    private var categoryIcon: String {
        switch exerciseData.category.lowercased() {
        case "chest": return "heart.fill"
        case "back": return "person.fill"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "hand.raised.fill"
        case "core": return "circle.circle"
        case "neck": return "person.crop.circle"
        default: return "figure.strengthtraining.traditional"
        }
    }
    
    // MARK: - Helper Functions
    
    private func extractSteps(from instructions: String?) -> [String]? {
        guard let instructions = instructions, !instructions.isEmpty else { return nil }
        
        var steps: [String] = []
        let pattern = "\\d+\\.\\s*([^\\d]+?)(?=\\d+\\.|$)"
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: instructions, options: [], range: NSRange(instructions.startIndex..., in: instructions))
            
            for match in matches {
                if match.numberOfRanges > 1 {
                    if let range = Range(match.range(at: 1), in: instructions) {
                        let step = String(instructions[range])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !step.isEmpty {
                            steps.append(step)
                        }
                    }
                }
            }
        }
        
        return steps.isEmpty ? nil : steps
    }
    
    private func getVideoURL(for exerciseName: String) -> URL? {
        let videoMapping = createExerciseVideoMapping()
        
        if let videoFilename = videoMapping[exerciseName] {
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let videoURL = documentsPath.appendingPathComponent(videoFilename)
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    return videoURL
                }
            }
            
            let nameWithoutExtension = String(videoFilename.dropLast(4))
            if let bundlePath = Bundle.main.path(forResource: nameWithoutExtension, ofType: "mp4") {
                return URL(fileURLWithPath: bundlePath)
            }
        }
        
        return nil
    }
}

// MARK: - Exercise Tip Row

struct ExerciseTipRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.subheadline)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Exercise Swap View

struct ExerciseSwapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let currentExercise: ExerciseData
    let programColor: Color
    let onSwap: (ExerciseData) -> Void
    
    @State private var searchText = ""
    @State private var allExercises: [ExerciseData] = []
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedExerciseForSwap: ExerciseData? = nil
    @State private var showingConfirmation = false
    @State private var scrollOffset: CGFloat = 0
    
    private let categories = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body"]
    private let equipmentTypes = ["All", "Bodyweight", "Dumbbells", "Barbell", "Cables", "Machines", "Kettlebell", "Bands"]
    
    private var filteredExercises: [ExerciseData] {
        allExercises.filter { exercise in
            // Don't show current exercise
            guard exercise.name != currentExercise.name else { return false }
            
            // Category filter
            let categoryMatch = selectedCategory == "All" || 
                exercise.category.localizedCaseInsensitiveContains(selectedCategory)
            
            // Equipment filter
            let equipmentMatch = selectedEquipment == "All" || 
                exercise.equipment.localizedCaseInsensitiveContains(selectedEquipment)
            
            // Search filter
            let searchMatch = searchText.isEmpty || 
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.category.localizedCaseInsensitiveContains(searchText)
            
            return categoryMatch && equipmentMatch && searchMatch
        }
    }
    
    var body: some View {
        ZStack {
            // Animated blue/cyan orb background
            AnimatedOrbBackground.exercises(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                swapHeader
                
                // Current exercise card
                currentExerciseCard
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 12)
                
                // Filter section
                filterSection
                    .padding(.top, 12)
                
                // Exercise list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredExercises, id: \.name) { exercise in
                            SwapExerciseCard(
                                exercise: exercise,
                                onSelect: {
                                    selectedExerciseForSwap = exercise
                                    showingConfirmation = true
                                }
                            )
                            .padding(.horizontal, Spacing.md)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
        }
        .onAppear {
            loadExercises()
        }
        .alert("Swap Exercise?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedExerciseForSwap = nil
            }
            Button("Swap") {
                if let newExercise = selectedExerciseForSwap {
                    onSwap(newExercise)
                    dismiss()
                }
            }
        } message: {
            if let newExercise = selectedExerciseForSwap {
                Text("Replace \"\(currentExercise.name)\" with \"\(newExercise.name)\"?")
            }
        }
    }
    
    // MARK: - Header
    private var swapHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(colorScheme == .dark ? Color(white: 0.2) : Color.white.opacity(0.9))
                .clipShape(Capsule())
            }
            
            Spacer()
            
            Text("Swap Exercise")
                .font(.headline)
                .fontWeight(.bold)
            
            Spacer()
            
            // Placeholder for balance
            Color.clear
                .frame(width: 60, height: 36)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Current Exercise Card
    private var currentExerciseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REPLACING")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(programColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: iconForCategory(currentExercise.category))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(programColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentExercise.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(currentExercise.category) • \(currentExercise.equipment)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.triangle.swap")
                    .font(.title3)
                    .foregroundColor(programColor)
            }
        }
        .padding(14)
        .background(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Filter Section
    private var filterSection: some View {
        VStack(spacing: 10) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search exercises...", text: $searchText)
                    .font(.subheadline)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(Spacing.sm)
            .background(colorScheme == .dark ? Color(white: 0.14) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 4, x: 0, y: 2)
            .padding(.horizontal, Spacing.md)
            
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        SwapFilterChip(
                            text: category,
                            isSelected: selectedCategory == category,
                            color: .blue
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            
            // Equipment filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equipmentTypes, id: \.self) { equipment in
                        SwapFilterChip(
                            text: equipment,
                            isSelected: selectedEquipment == equipment,
                            color: .orange
                        ) {
                            selectedEquipment = equipment
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }
    
    // MARK: - Helper Functions
    private func loadExercises() {
        allExercises = ExerciseDataProvider.shared.exercises
    }
    
    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}

// MARK: - Swap Filter Chip
struct SwapFilterChip: View {
    let text: String
    let isSelected: Bool
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    isSelected ? color : color.opacity(0.1)
                )
                .clipShape(Capsule())
        }
    }
}

// MARK: - Swap Exercise Card
struct SwapExerciseCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let exercise: ExerciseData
    let onSelect: () -> Void
    
    private var categoryColor: Color {
        switch exercise.category.lowercased() {
        case "chest": return .purple
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "neck": return .indigo
        default: return .cyan
        }
    }
    
    private var categoryGradient: [Color] {
        switch exercise.category.lowercased() {
        case "chest": return [Color.purple, Color.pink]
        case "back": return [Color.blue, Color.cyan]
        case "legs": return [Color.green, Color.teal]
        case "shoulders": return [Color.orange, Color.yellow]
        case "arms": return [Color.purple, Color.indigo]
        case "core": return [Color.yellow, Color.orange]
        case "full body": return [Color.pink, Color.red]
        default: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
    
    private var categoryIcon: String {
        let exerciseName = exercise.name.lowercased()
        
        if exerciseName.contains("dumbbell") {
            return "dumbbell.fill"
        } else if exerciseName.contains("barbell") {
            return "figure.strengthtraining.traditional"
        } else if exerciseName.contains("cable") {
            return "dot.radiowaves.left.and.right"
        } else if exerciseName.contains("squat") {
            return "figure.squat"
        } else if exerciseName.contains("press") {
            return "arrow.up.circle.fill"
        } else if exerciseName.contains("curl") {
            return "figure.arms.open"
        } else if exerciseName.contains("row") {
            return "arrow.left.and.right.circle.fill"
        }
        
        switch exercise.category.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.climbing"
        case "legs": return "figure.squat"
        case "shoulders": return "arrow.up.circle.fill"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Compact exercise icon with vibrant gradient (matching exercise library)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: categoryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: categoryGradient[0].opacity(0.25), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: categoryIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(exercise.category)
                            .font(.caption)
                            .foregroundColor(categoryColor)
                            .fontWeight(.medium)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(exercise.equipment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Chevron (matching exercise library style)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - category colored (subtle)
                    RoundedRectangle(cornerRadius: 28)
                        .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                        .offset(y: 4)
                        .blur(radius: 2)
                    
                    // Middle shadow layer (subtle)
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                        .offset(y: 2)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 25)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color(white: 0.15), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.98)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color.white.opacity(0.08), Color.clear]
                                    : [Color.white, Color.white.opacity(0.3), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    
                    // Subtle accent border
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                    categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
            .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationStack {
        CloudProgramScheduleView()
            .environmentObject(WorkoutManager.shared)
    }
}

