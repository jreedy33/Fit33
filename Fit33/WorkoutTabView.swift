import SwiftUI
import CoreData

struct WorkoutTabView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        ZStack {
            // Layer 1: Navigation Stack (always present)
            NavigationStack(path: $navigationPath) {
                WorkoutHomeView(navigationPath: $navigationPath)
                    .navigationBarHidden(true)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .navigationDestination(for: String.self) { destination in
                        navigationDestinationView(for: destination)
                    }
            }
            
            // Layer 2: Transition overlay - hides navigation during transitions
            if (workoutManager.shouldClearWorkoutTabNav && !workoutManager.isWorkoutActive) || workoutManager.isTransitioningBackToHome {
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10)]
                        : [Color.blue.opacity(0.15), Color.purple.opacity(0.08)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .zIndex(5)
            }
            
            // Layer 3: Active Workout (on top when active)
            if workoutManager.isWorkoutActive,
               let workout = workoutManager.currentWorkout,
               !workoutManager.currentExercises.isEmpty {
                ActiveWorkoutView(
                    isPresented: .constant(true),
                    workout: workout,
                    exercises: workoutManager.currentExercises
                )
                .zIndex(10)
            } else if workoutManager.isWorkoutActive && workoutManager.currentExercises.isEmpty {
                // Safety: If workout is active but exercises are empty, auto-clear the stuck state
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Workout Data Error")
                        .font(.title2.bold())
                    
                    Text("Your workout data is corrupted. Tap below to clear it and start fresh.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        workoutManager.forceResetWorkoutState()
                    } label: {
                        Text("Clear Stuck Workout")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .zIndex(10)
            }
        }
        .onAppear {
            if workoutManager.shouldShowWorkoutGenerator {
                navigationPath.append("WorkoutGenerator")
                workoutManager.shouldShowWorkoutGenerator = false
            }
        }
        .onReceive(deepLinkManager.$pendingDestination) { destination in
            // Handle deep links from Live Activity and Notifications
            guard let destination = destination else { return }
            switch destination {
            case .running:
                // Navigate to running workout view
                navigationPath.append("OutdoorRun")
                deepLinkManager.pendingDestination = nil
                print("🏃 Deep link: Navigating to running workout")
            case .workout:
                // Navigate to workout generator
                navigationPath.append("WorkoutGenerator")
                deepLinkManager.pendingDestination = nil
                print("🏋️ Deep link: Navigating to workout generator")
            case .dashboard:
                // Already on workout tab, no navigation needed
                deepLinkManager.pendingDestination = nil
            case .sharedWorkout:
                // Shared workouts are handled by the sheet in MainTabView
                // Just consume the destination here
                deepLinkManager.pendingDestination = nil
                print("🔗 Deep link: Shared workout will be displayed in sheet")
            case .receivedWorkout(let workoutId):
                // Navigate to received workouts and open specific workout
                deepLinkManager.pendingReceivedWorkoutId = workoutId
                navigationPath.append("ReceivedWorkouts")
                deepLinkManager.pendingDestination = nil
                print("📬 Deep link: Navigating to received workout \(workoutId)")
            case .receivedWorkouts:
                // Navigate to received workouts list
                navigationPath.append("ReceivedWorkouts")
                deepLinkManager.pendingDestination = nil
                print("📬 Deep link: Navigating to received workouts")
            case .friends:
                // Navigate to friends list
                navigationPath.append("FriendsList")
                deepLinkManager.pendingDestination = nil
                print("👥 Deep link: Navigating to friends list")
            case .friendRequests:
                // Navigate directly to friend requests tab
                navigationPath.append("FriendRequests")
                deepLinkManager.pendingDestination = nil
                print("👥 Deep link: Navigating to friend requests tab")
                
            // Challenge destinations
            case .challenges:
                // Navigate to challenges list
                navigationPath.append("ChallengesList")
                deepLinkManager.pendingDestination = nil
                print("🏆 Deep link: Navigating to challenges list")
            case .challengeInvite(let challengeId):
                // Navigate to challenge invite
                navigationPath.append("ChallengeInvite-\(challengeId)")
                deepLinkManager.pendingDestination = nil
                print("🏆 Deep link: Navigating to challenge invite \(challengeId)")
            case .challengeDetail(let challengeId):
                // Navigate to challenge detail
                navigationPath.append("ChallengeDetail-\(challengeId)")
                deepLinkManager.pendingDestination = nil
                print("🏆 Deep link: Navigating to challenge detail \(challengeId)")
                
            // These destinations are handled by MainTabView (tab switching)
            case .mealsTab, .statsTab, .hydration, .stepTracker, .weightTracker, .workoutHistory, .personalRecord, .streakInfo:
                // Already handled by MainTabView, just clear the destination
                deepLinkManager.pendingDestination = nil
            }
        }
        .onChange(of: workoutManager.shouldShowWorkoutGenerator) { _, shouldShow in
            // 🔧 Handle auto-gen redirect from Home tab
            if shouldShow {
                navigationPath.append("WorkoutGenerator")
                workoutManager.shouldShowWorkoutGenerator = false
            }
        }
        .onChange(of: workoutManager.shouldNavigateToPrograms) { _, shouldShow in
            // 🔧 Handle programs redirect from Home tab
            if shouldShow {
                navigationPath.append("PersonalizedPrograms")
                workoutManager.shouldNavigateToPrograms = false
            }
        }
        .onChange(of: workoutManager.shouldClearWorkoutTabNav) { _, shouldClear in
            if shouldClear {
                navigationPath = NavigationPath()
            }
        }
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            if isActive {
                navigationPath = NavigationPath()
            }
        }
        .onChange(of: workoutManager.shouldNavigateToProgramOverview) { _, shouldNavigate in
            // 🔧 Navigate to Program Overview from Dashboard
            if shouldNavigate {
                navigationPath = NavigationPath()  // Clear first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    navigationPath.append("SmartProgramOverview")
                    workoutManager.shouldNavigateToProgramOverview = false
                }
            }
        }
        .onChange(of: workoutManager.shouldNavigateToProgramDay) { _, shouldNavigate in
            // 🔧 Navigate to Program Day from Dashboard
            if shouldNavigate {
                navigationPath = NavigationPath()  // Clear first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    navigationPath.append("SmartProgramDay")
                    workoutManager.shouldNavigateToProgramDay = false
                }
            }
        }
    }
    
    // MARK: - Navigation Destination Helper
    // Extracted to reduce body complexity for compiler
    @ViewBuilder
    private func navigationDestinationView(for destination: String) -> some View {
        switch destination {
        case "WorkoutGenerator":
            WorkoutGeneratorSelectionView()
        case "GeneratedPrograms":
            GeneratedProgramsListView()
        case "ProgramLibrary":
            CloudProgramLibraryView()
        case "ProgramExplorer":
            ProgramExplorerView()
        case "PersonalizedPrograms":
            PersonalizedProgramsView()
        case "CloudProgramSchedule":
            CloudProgramScheduleView()
        case "CustomWorkout":
            CustomWorkoutBuilderView()
        case "FavoriteRoutines":
            FavoriteRoutinesView()
        case "OutdoorRun":
            RunningWorkoutView()
        case "SmartProgramOverview":
            if let program = workoutManager.navigateProgramData {
                SmartProgramOverviewView(
                    program: program,
                    template: workoutManager.navigateProgramTemplate
                )
                .environmentObject(workoutManager)
                .environmentObject(userManager)
            }
        case "SmartProgramDay":
            if let program = workoutManager.navigateProgramData,
               let day = workoutManager.navigateProgramDay {
                SmartProgramDayPreviewView(
                    program: program,
                    day: day,
                    programName: program.personalizedName,
                    totalDays: program.generatedDays.count
                )
                .environmentObject(workoutManager)
                .environmentObject(userManager)
            }
        case "ReceivedWorkouts":
            ReceivedWorkoutsView()
        case "FriendsList":
            FriendsListView()
        case "FriendRequests":
            FriendsListView(initialTab: 1)  // Navigate directly to Requests tab
        default:
            if destination.hasPrefix("ProgramDetail:") {
                let programId = String(destination.dropFirst("ProgramDetail:".count))
                CloudProgramDetailView(programId: programId)
            } else {
                EmptyView()
            }
        }
    }
}

struct WorkoutHomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @Binding var navigationPath: NavigationPath
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        animation: .none)  // Disable animation for faster updates
    private var workouts: FetchedResults<Workout>
    @State private var forceRenderID = UUID()
    @State private var isNavigating = false  // 🔧 Debounce protection
    @State private var showingEquipmentConnection = false
    @ObservedObject private var cloudProgramService = CloudProgramService.shared
    @ObservedObject private var generatedProgramService = GeneratedProgramService.shared
    
    // Cardio workouts for combined goal tracking (includes Strava activities)
    @State private var cardioWorkoutsThisWeek: [CardioWorkoutDTO] = []
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                Color.clear.frame(height: 0).id("top")
                
                VStack(spacing: 0) {
                // Custom header
                customWorkoutHeaderView
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                
                // Content with spacing
                VStack(spacing: 20) {
                    // Quick Actions
                    quickActionsSection
                        .id(forceRenderID)
                    
                    // Cardio Section - Outdoor Run
                    cardioSection
                    
                    // Smart Active Program Widget (when user has an active generated program)
                    if let activeProgram = generatedProgramService.activeProgram {
                        smartGeneratedProgramWidget(program: activeProgram)
                    }
                    // Show program recommendations if no active program but programs exist
                    else if !generatedProgramService.generatedPrograms.isEmpty {
                        programRecommendationsWidget
                    }
                    // Legacy fallback
                    else {
                        recommendedWorkoutSection
                    }
                    
                    // Next Goals (Revamped "Almost There!")
                    nextGoalsSection
                    
                    // Recent Activity
                    recentActivitySection
                        .id(forceRenderID)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
            }
            .onAppear {
                // Force immediate rendering
                forceRenderID = UUID()
            }
            .task {
                // Load cardio workouts (includes Strava activities) for goal tracking
                await loadCardioWorkoutsThisWeek()
            }
            .background(
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
            )
            .onChange(of: scrollToTopTrigger) { _, _ in
                scrollProxy.scrollTo("top", anchor: .top)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $showingEquipmentConnection) {
            FitnessEquipmentView()
        }
    }
    
    // MARK: - Custom Header View
    private var customWorkoutHeaderView: some View {
        HStack {
            Text("Workout")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .green, .green, Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .green.opacity(0.4), radius: 6, x: 0, y: 2)
            
            Spacer()
            
            // Active workout timer (only shows when workout is active)
            if WorkoutManager.shared.isWorkoutActive {
                Text(WorkoutManager.shared.formattedDuration)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.leading, 4)
    }
    
    // MARK: - Cardio Section
    @State private var showingCardioLanding = false
    @State private var showingStretchMode = false
    
    private var cardioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cardio & Stretch Row - Two compact buttons side by side
            HStack(spacing: 12) {
                // Cardio Button
                Button(action: {
                    guard !isNavigating else { return }
                    isNavigating = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNavigating = false }
                    
                    HapticManager.impact(.medium)
                    showingCardioLanding = true
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(colors: [Color.green.opacity(0.3), Color.mint.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "figure.run")
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cardio")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Run • Cycle • Row")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer(minLength: 0)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(colors: [Color.green.opacity(0.3), Color.mint.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                
                // Stretch Button
                Button(action: {
                    guard !isNavigating else { return }
                    isNavigating = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNavigating = false }
                    
                    HapticManager.impact(.medium)
                    showingStretchMode = true
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "figure.flexibility")
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stretch")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Recovery • Mobility")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer(minLength: 0)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingCardioLanding) {
            CardioLandingView()
                .environmentObject(userManager)
        }
        .sheet(isPresented: $showingStretchMode) {
            StretchModeView()
                .environmentObject(userManager)
        }
    }
    
    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                // Custom Workout Button (using DepthQuickActionCard for dark mode support)
                DepthQuickActionCard(
                    title: "Custom Workout",
                    subtitle: "Build your own",
                    icon: "plus.circle.fill",
                    gradient: [Color.blue, Color.cyan],
                    action: {
                        // 🔧 Debounce: Prevent double-taps
                        guard !isNavigating else { return }
                        isNavigating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNavigating = false }
                        
                        // 🔧 Clear any pending home tab navigation
                        WorkoutManager.shared.shouldNavigateToHomeTab = false
                        
                        SessionLogManager.shared.logTap("Custom Workout", screen: .workoutTab, element: .dashboardCustomButton)
                        SessionLogManager.shared.beginTransition(to: .customWorkoutBuilder, action: "custom_workout_tap")
                        navigationPath.append("CustomWorkout")
                    }
                )
                
                // Auto Workout Button (using DepthQuickActionCard for dark mode support)
                DepthQuickActionCard(
                    title: "Auto Workout",
                    subtitle: "Auto-generated routine",
                    icon: "dumbbell.fill",
                    gradient: [Color.purple, Color.pink],
                    action: {
                        // 🔧 Debounce: Prevent double-taps
                        guard !isNavigating else { return }
                        isNavigating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNavigating = false }
                        
                        // 🔧 Clear any pending home tab navigation (prevents race condition)
                        WorkoutManager.shared.shouldNavigateToHomeTab = false
                        
                        SessionLogManager.shared.logTap("Auto Workout", screen: .workoutTab, element: .dashboardAutoGenButton)
                        SessionLogManager.shared.beginTransition(to: .workoutGenerator, action: "auto_workout_tap")
                        navigationPath.append("WorkoutGenerator")
                    }
                )
                
                // Training Programs
                DepthQuickActionCard(
                    title: "Training Programs",
                    subtitle: "10 personalized programs",
                    icon: "calendar.badge.checkmark",
                    gradient: [Color.green, Color.teal],
                    action: {
                        guard !isNavigating else { return }
                        isNavigating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNavigating = false }
                        
                        SessionLogManager.shared.logTap("Training Programs", screen: .workoutTab)
                        SessionLogManager.shared.beginTransition(to: .programsList, action: "training_programs_tap")
                        navigationPath.append("PersonalizedPrograms")
                    }
                )
                
                // Favorite Routines
                DepthQuickActionCard(
                    title: "Favorites",
                    subtitle: "Your saved routines",
                    icon: "star.fill",
                    gradient: [Color.orange, Color.yellow],
                    action: {
                        guard !isNavigating else { return }
                        isNavigating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNavigating = false }
                        
                        navigationPath.append("FavoriteRoutines")
                    }
                )
            }
        }
    }
    
    // MARK: - Smart Generated Program Widget
    private func smartGeneratedProgramWidget(program: DynamicProgramGenerator.GeneratedProgram) -> some View {
        let displayInfo = generatedProgramService.getDisplayInfo(for: program)
        let programColor = colorForProgramType(program.programType)
        
        return VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Active Program")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: program.icon)
                    .foregroundStyle(
                        LinearGradient(colors: [programColor, programColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
            }
            .padding(.horizontal, 4)
            
            // Program card
            VStack(spacing: 0) {
                // Program info
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [programColor, programColor.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: program.icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(program.name)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        Text("Week \(displayInfo.currentWeek) • \(displayInfo.progressText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .trim(from: 0, to: displayInfo.progressPercentage / 100)
                            .stroke(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(displayInfo.progressPercentage))%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(programColor)
                    }
                }
                .padding(16)
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Today's workout with rounded inner card
                if let currentDay = generatedProgramService.currentDay {
                    NavigationLink(destination: SmartWorkoutPreviewView(
                        day: currentDay,
                        program: program
                    ).environmentObject(generatedProgramService)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Today's Workout")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(currentDay.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 12) {
                                    Label("\(currentDay.exercises.count) exercises", systemImage: "dumbbell.fill")
                                    Label("~\(currentDay.estimatedDuration) min", systemImage: "clock.fill")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("GO!")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(
                                        colors: [programColor, programColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.5), programColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
        }
    }
    
    // MARK: - Program Recommendations Widget
    private var programRecommendationsWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Your Programs")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                NavigationLink(destination: GeneratedProgramsListView()) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 4)
            
            // Program cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(generatedProgramService.generatedPrograms.prefix(3)) { program in
                        WorkoutTabProgramCard(
                            program: program,
                            onStart: {
                                generatedProgramService.startProgram(program)
                            }
                        )
                        .frame(width: 260)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // Helper function for program type color
    private func colorForProgramType(_ type: DynamicProgramGenerator.GeneratedProgram.ProgramType) -> Color {
        switch type {
        case .hypertrophy: return .blue
        case .strength: return .red
        case .fatLoss: return .orange
        case .toning: return .purple
        case .generalFitness: return .green
        case .powerbuilding: return .yellow
        }
    }
    
    // MARK: - Smart Workout Insights Widget (Legacy)
    private var smartWorkoutInsightsWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Floating header outside the card
            HStack {
                Text("Training Insights")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
            }
            .padding(.horizontal, 4)
            
            // The card itself
            SmartInsightsCard(
                workouts: Array(workouts),
                todayExercises: getTodaysProgramExercises(),
                onViewProgram: {
                    navigationPath.append("CloudProgramSchedule")
                }
            )
        }
    }
    
    // Helper to get today's program exercises
    private func getTodaysProgramExercises() -> [String] {
        guard let progress = cloudProgramService.activeProgram,
              let dayDetails = cloudProgramService.getDayDetails(for: progress.currentDay) else {
            return []
        }
        return dayDetails.exercises.map { $0.exercise.exerciseName }
    }
    
    // MARK: - Smart Program Recommendation Widget (Legacy)
    private var recommendedWorkoutSection: some View {
        SmartProgramWidget(
            user: userManager.currentUser,
            onViewProgram: { programId in
                if let programId = programId {
                    // Navigate directly to the program detail page
                    navigationPath.append("ProgramDetail:\(programId)")
                } else {
                    // Fallback to program library
                    navigationPath.append("ProgramLibrary")
                }
            }
        )
    }
    
    // MARK: - Next Goals Section (Revamped "Almost There!")
    private var nextGoalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Next Goals")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Tap to take action")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "target")
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
            }
            .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let goals = generateNextGoals()
                    if goals.isEmpty {
                        EmptyNextGoalsCard()
                    } else {
                        ForEach(goals) { goal in
                            NextGoalCard(goal: goal) { action in
                                handleGoalAction(action)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }
    
    // Handle goal card tap actions
    private func handleGoalAction(_ action: GoalAction) {
        // 🔧 Debounce: Prevent double-taps
        guard !isNavigating else { return }
        
        switch action {
        case .startWorkout(let focus):
            isNavigating = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isNavigating = false }
            // Navigate to workout generator with optional muscle focus
            navigationPath.append("WorkoutGenerator")
        case .viewAchievements, .viewProgress:
            // Could navigate to a dedicated achievements/progress view
            // For now, this is informational
            break
        case .none:
            break
        }
    }
    
    // MARK: - Goal Generation
    private func generateNextGoals() -> [NextGoal] {
        var goals: [NextGoal] = []
        
        let totalWorkouts = workouts.count
        let currentStreak = Int(userManager.currentUser?.currentStreak ?? 0)
        let longestStreak = Int(userManager.currentUser?.longestStreak ?? 0)
        let userLevel = userManager.getLevel()
        let userXP = Int(userManager.currentUser?.xp ?? 0)
        let workoutsThisWeek = calculateWorkoutsThisWeek()
        let workoutsToday = calculateWorkoutsToday()
        
        // Calculate workout stats
        let heaviestWeight = calculateHeaviestWeight()
        
        // 1. DAILY CHALLENGE - Workout today (if haven't already)
        if workoutsToday == 0 {
            goals.append(NextGoal(
                id: "daily_workout",
                type: .dailyChallenge,
                title: "Daily Workout",
                subtitle: "Complete a workout today",
                icon: "sun.max.fill",
                progress: 0.0,
                remaining: "1 workout to go",
                timeContext: "today",
                accentColor: .orange,
                action: .startWorkout(focus: nil),
                priority: 1,
                xpReward: 50
            ))
        }
        
        // 2. WEEKLY CHALLENGE - Hit weekly target
        let weeklyTarget = 4 // Aim for 4 workouts per week
        if workoutsThisWeek < weeklyTarget {
            let remaining = weeklyTarget - workoutsThisWeek
            goals.append(NextGoal(
                id: "weekly_target",
                type: .weeklyChallenge,
                title: "Weekly Target",
                subtitle: "Hit your weekly goal",
                icon: "calendar.badge.checkmark",
                progress: Double(workoutsThisWeek) / Double(weeklyTarget),
                remaining: "\(remaining) more workout\(remaining == 1 ? "" : "s")",
                timeContext: "this week",
                accentColor: .blue,
                action: .startWorkout(focus: nil),
                priority: 2,
                xpReward: 100
            ))
        }
        
        // 3. STREAK MAINTENANCE - Keep the streak alive
        if currentStreak > 0 && workoutsToday == 0 {
            goals.append(NextGoal(
                id: "streak_maintain",
                type: .streakMaintain,
                title: "Keep the Fire!\(currentStreak >= 7 ? " 🔥" : "")",
                subtitle: "\(currentStreak)-day streak active",
                icon: "flame.fill",
                progress: min(0.9, Double(currentStreak) / 30.0), // Visual progress toward 30-day goal
                remaining: "Workout today to continue",
                timeContext: nil,
                accentColor: currentStreak >= 7 ? .red : .orange,
                action: .startWorkout(focus: nil),
                priority: 0, // Highest priority if streak is at risk
                xpReward: currentStreak >= 7 ? 75 : 25
            ))
        }
        
        // 4. WORKOUT MILESTONE - Next workout count achievement
        let workoutMilestones = [5, 10, 25, 50, 75, 100, 150, 200, 250, 300, 500, 750, 1000]
        if let nextMilestone = workoutMilestones.first(where: { $0 > totalWorkouts }) {
            let remaining = nextMilestone - totalWorkouts
            let progress = Double(totalWorkouts) / Double(nextMilestone)
            
            if progress >= 0.5 { // Only show if at least 50% there
                goals.append(NextGoal(
                    id: "workout_milestone_\(nextMilestone)",
                    type: .achievement,
                    title: getMilestoneTitle(nextMilestone),
                    subtitle: "Complete \(nextMilestone) workouts",
                    icon: getWorkoutMilestoneIcon(nextMilestone),
                    progress: progress,
                    remaining: "\(remaining) workout\(remaining == 1 ? "" : "s") to go",
                    timeContext: nil,
                    accentColor: getMilestoneColor(nextMilestone),
                    action: .startWorkout(focus: nil),
                    priority: 5,
                    xpReward: nextMilestone >= 100 ? 500 : (nextMilestone >= 50 ? 250 : 100)
                ))
            }
        }
        
        // 5. STREAK MILESTONE - Next streak achievement
        let streakMilestones = [7, 14, 21, 30, 60, 90, 180, 365]
        let activeStreak = max(currentStreak, longestStreak)
        if let nextStreakMilestone = streakMilestones.first(where: { $0 > currentStreak }) {
            let progress = Double(currentStreak) / Double(nextStreakMilestone)
            
            if progress >= 0.4 && currentStreak > 0 { // Only show if at least 40% there
                let remaining = nextStreakMilestone - currentStreak
                goals.append(NextGoal(
                    id: "streak_milestone_\(nextStreakMilestone)",
                    type: .achievement,
                    title: getStreakMilestoneTitle(nextStreakMilestone),
                    subtitle: "Reach a \(nextStreakMilestone)-day streak",
                    icon: "flame.fill",
                    progress: progress,
                    remaining: "\(remaining) day\(remaining == 1 ? "" : "s") remaining",
                    timeContext: nil,
                    accentColor: .red,
                    action: .startWorkout(focus: nil),
                    priority: 4,
                    xpReward: nextStreakMilestone >= 30 ? 300 : 150
                ))
            }
        }
        
        // 6. LEVEL UP - Close to next level
        let xpForNextLevel = (userLevel + 1) * 100 // Simple XP calculation
        let xpProgress = Double(userXP) / Double(xpForNextLevel)
        if xpProgress >= 0.6 {
            let xpRemaining = xpForNextLevel - userXP
            goals.append(NextGoal(
                id: "level_up",
                type: .levelUp,
                title: "Level \(userLevel + 1) Awaits!",
                subtitle: "Keep grinding to level up",
                icon: "arrow.up.circle.fill",
                progress: xpProgress,
                remaining: "\(xpRemaining) XP needed",
                timeContext: nil,
                accentColor: .purple,
                action: .startWorkout(focus: nil),
                priority: 6,
                xpReward: nil
            ))
        }
        
        // 7. WEIGHT MILESTONE - Next lifting achievement (if lifting heavy)
        if heaviestWeight > 50 {
            let weightMilestones = [100, 135, 185, 225, 275, 315, 365, 405, 495, 500]
            if let nextWeightMilestone = weightMilestones.first(where: { Double($0) > heaviestWeight }) {
                let progress = heaviestWeight / Double(nextWeightMilestone)
                
                if progress >= 0.7 { // Only show if 70%+ there
                    let remaining = Double(nextWeightMilestone) - heaviestWeight
                    goals.append(NextGoal(
                        id: "weight_milestone_\(nextWeightMilestone)",
                        type: .personalRecord,
                        title: getWeightMilestoneTitle(nextWeightMilestone),
                        subtitle: "Lift \(nextWeightMilestone) lbs",
                        icon: "scalemass.fill",
                        progress: progress,
                        remaining: "\(Int(remaining)) lbs to go",
                        timeContext: nil,
                        accentColor: .green,
                        action: .startWorkout(focus: nil),
                        priority: 7,
                        xpReward: 200
                    ))
                }
            }
        }
        
        // Sort by priority and limit to 5 goals
        return goals.sorted { $0.priority < $1.priority }.prefix(5).map { $0 }
    }
    
    // MARK: - Goal Helper Functions
    
    /// Load cardio workouts (including Strava activities) for this week
    private func loadCardioWorkoutsThisWeek() async {
        do {
            let cardioWorkouts = try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 50)
            await MainActor.run {
                self.cardioWorkoutsThisWeek = cardioWorkouts
            }
        } catch {
            print("⚠️ [GOALS] Failed to load cardio workouts: \(error)")
        }
    }
    
    /// Calculate total workouts this week (strength + cardio/Strava)
    private func calculateWorkoutsThisWeek() -> Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        
        // Count strength workouts
        let strengthCount = workouts.filter { ($0.date ?? Date.distantPast) >= startOfWeek }.count
        
        // Count cardio workouts (includes Strava activities)
        let cardioCount = cardioWorkoutsThisWeek.filter {
            ISO8601Parser.parse($0.completedAt, fallback: Date.distantPast) >= startOfWeek
        }.count
        
        return strengthCount + cardioCount
    }
    
    /// Calculate total workouts today (strength + cardio/Strava)
    private func calculateWorkoutsToday() -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        
        // Count strength workouts
        let strengthCount = workouts.filter { ($0.date ?? Date.distantPast) >= startOfDay }.count
        
        // Count cardio workouts (includes Strava activities)
        let cardioCount = cardioWorkoutsThisWeek.filter {
            ISO8601Parser.parse($0.completedAt, fallback: Date.distantPast) >= startOfDay
        }.count
        
        return strengthCount + cardioCount
    }
    
    private func getMilestoneTitle(_ count: Int) -> String {
        switch count {
        case 5: return "Getting Started"
        case 10: return "Double Digits"
        case 25: return "Quarter Century"
        case 50: return "Half Century"
        case 75: return "Going Strong"
        case 100: return "Century Club"
        case 150: return "Dedicated"
        case 200: return "Committed"
        case 250: return "Iron Will"
        case 300: return "Legend Status"
        case 500: return "Elite Athlete"
        case 750: return "Gym Warrior"
        case 1000: return "Thousand Strong"
        default: return "\(count) Workouts"
        }
    }
    
    private func getWorkoutMilestoneIcon(_ count: Int) -> String {
        switch count {
        case 1...10: return "figure.walk"
        case 11...50: return "figure.run"
        case 51...100: return "figure.strengthtraining.traditional"
        case 101...250: return "medal.fill"
        case 251...500: return "trophy.fill"
        default: return "crown.fill"
        }
    }
    
    private func getMilestoneColor(_ count: Int) -> Color {
        switch count {
        case 1...10: return .blue
        case 11...50: return .green
        case 51...100: return .orange
        case 101...250: return .purple
        case 251...500: return .red
        default: return .yellow
        }
    }
    
    private func getStreakMilestoneTitle(_ days: Int) -> String {
        switch days {
        case 7: return "One Week Warrior"
        case 14: return "Two Week Titan"
        case 21: return "Three Week Hero"
        case 30: return "Monthly Master"
        case 60: return "Two Month Legend"
        case 90: return "Quarterly Champion"
        case 180: return "Half Year Hero"
        case 365: return "Year of Iron"
        default: return "\(days)-Day Streak"
        }
    }
    
    private func getWeightMilestoneTitle(_ weight: Int) -> String {
        switch weight {
        case 100: return "Century Lift"
        case 135: return "One Plate Club"
        case 185: return "Rising Power"
        case 225: return "Two Plate Club"
        case 275: return "Getting Heavy"
        case 315: return "Three Plate Club"
        case 365: return "Power Lifter"
        case 405: return "Four Plate Club"
        case 495: return "Almost 500"
        case 500: return "Half Ton Hero"
        default: return "\(weight) lbs"
        }
    }
    
    // MARK: - Recent Activity
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with stats
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("\(workouts.count) workouts completed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                NavigationLink(destination: WorkoutHistoryFullView()) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
            }
            
            // Workout cards with enhanced design
            if workouts.isEmpty {
                EmptyRecentActivityCard()
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(workouts.prefix(3).enumerated()), id: \.element.id) { index, workout in
                        RecentWorkoutCard(workout: workout, isMostRecent: index == 0)
                    }
                }
            }
        }
        .padding(24)
        .background(
            ZStack {
                // Clean gradient background matching EnhancedStatCard
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.15), Color(white: 0.10)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle top highlight
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 4)
    }
    
    // Get the glow color based on the most recent workout's muscle group (kept for card content)
    private var recentActivityGlowColor: Color {
        guard let mostRecentWorkout = workouts.first else {
            return .blue // Default fallback
        }
        
        // Get exercises from most recent workout
        let exercises = mostRecentWorkout.exercises?.allObjects as? [WorkoutExercise] ?? []
        let muscles = exercises.compactMap { ($0.exercise?.muscleGroups as? [String])?.first?.lowercased() }
        let primaryMuscle = muscles.first ?? ""
        
        switch primaryMuscle {
        case "chest": return .red
        case "back": return .blue
        case "legs", "quads", "hamstrings", "glutes": return .green
        case "shoulders": return .orange
        case "biceps", "triceps", "arms": return .purple
        case "core", "abs": return .yellow
        default:
            // Fallback to time-based color
            let hour = Calendar.current.component(.hour, from: mostRecentWorkout.date ?? Date())
            if hour >= 5 && hour < 12 {
                return .orange
            } else if hour >= 12 && hour < 17 {
                return .blue
            } else {
                return .purple
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getRecommendedProgram() -> SuggestedProgram {
        // Use Smart Program Recommender for personalized recommendations
        // Considers: equipment, goals, experience, age, training history, and more
        guard let user = userManager.currentUser else {
            return getDefaultProgram()
        }
        
        return SmartProgramRecommender.shared.getSuggestedProgram(for: user)
    }
    
    private func getDefaultProgram() -> SuggestedProgram {
        SuggestedProgram(
            title: "Total Fitness Starter",
            description: "Well-rounded program for overall health and fitness. Start your journey here.",
            duration: "6 weeks",
            workoutsPerWeek: "3 days/week",
            focusAreas: ["Full Body", "Functional Fitness", "Habit Building"],
            difficulty: "Beginner",
            primaryColor: .green,
            secondaryColor: .mint,
            icon: "figure.cooldown",
            callToAction: "Start Journey"
        )
    }
    
    private func daysSince(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
    
    // MARK: - Statistics Calculation Helpers
    
    private func calculateHeaviestWeight() -> Double {
        return workouts.reduce(0.0) { maxWeight, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return maxWeight }
            let workoutMax = exercises.reduce(0.0) { exerciseMax, exercise in
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return exerciseMax }
                let exerciseMaxWeight = sets.map { $0.weight }.max() ?? 0
                return max(exerciseMax, exerciseMaxWeight)
            }
            return max(maxWeight, workoutMax)
        }
    }
    
    private func calculateHighestReps() -> Int {
        return workouts.reduce(0) { maxReps, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return maxReps }
            let workoutMax = exercises.reduce(0) { exerciseMax, exercise in
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return exerciseMax }
                let exerciseMaxReps = sets.map { Int($0.reps) }.max() ?? 0
                return max(exerciseMax, exerciseMaxReps)
            }
            return max(maxReps, workoutMax)
        }
    }
    
    private func calculateLongestWorkoutMinutes() -> Int {
        return workouts.map { Int($0.duration / 60) }.max() ?? 0
    }
    
    private func calculateMostSetsInWorkout() -> Int {
        return workouts.reduce(0) { maxSets, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return maxSets }
            let workoutSets = exercises.reduce(0) { total, exercise in
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return total }
                return total + sets.count
            }
            return max(maxSets, workoutSets)
        }
    }
    
    private func calculateWorkoutsThisMonth() -> Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startOfMonth
        }.count
    }
}

// MARK: - Supporting Data Structures

struct SuggestedProgram {
    let title: String
    let description: String
    let duration: String
    let workoutsPerWeek: String
    let focusAreas: [String]
    let difficulty: String
    let primaryColor: Color
    let secondaryColor: Color
    let icon: String
    let callToAction: String
}

struct NearAchievement {
    let id: String
    let title: String
    let description: String
    let progress: Double
    let icon: String
    let color: Color
}

// MARK: - Card Components

struct QuickActionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 5, x: 0, y: 3)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 160, height: 140)
            .background(Color.cardBackground)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cardBackground)
                    .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Depth Quick Action Card (with 3D effect)
struct DepthQuickActionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    let action: () -> Void
    
    private var cardBackgroundGradient: [Color] {
        colorScheme == .dark 
            ? [Color.darkCardBackground, Color.darkSurface]
            : [Color.white, Color.white.opacity(0.95)]
    }
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: gradient.first?.opacity(0.4) ?? .clear, radius: 8, x: 0, y: 4)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 160, height: 140)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored based on gradient
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill((gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBackgroundGradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.4 : 0.3),
                                    (gradient.last ?? .gray).opacity(colorScheme == .dark ? 0.3 : 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(WorkoutDepthButtonStyle())
    }
}

// MARK: - Depth Button Style
struct WorkoutDepthButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Smart Program Widget
struct SmartProgramWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let user: User?
    let onViewProgram: (String?) -> Void  // Passes program ID
    
    @State private var recommendation: ProgramRecommendation?
    @State private var isLoading = true
    
    private var matchScore: Int {
        Int(recommendation?.matchScore ?? 0)
    }
    
    private var matchColor: Color {
        if matchScore >= 200 { return .green }
        if matchScore >= 150 { return .blue }
        if matchScore >= 100 { return .orange }
        return .gray
    }
    
    private var matchLabel: String {
        if matchScore >= 200 { return "Excellent Match" }
        if matchScore >= 150 { return "Great Match" }
        if matchScore >= 100 { return "Good Match" }
        return "Suggested"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Perfect Program")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let user = user {
                        Text("Based on your \(user.fitnessGoal ?? "fitness") goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Star icon
                Image(systemName: "star.fill")
                    .font(.title3)
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, 4)
            
            // Widget Card
            if isLoading {
                loadingCard
            } else if let recommendation = recommendation {
                smartProgramCard(recommendation)
            } else {
                fallbackCard
            }
        }
        .onAppear {
            loadRecommendation()
        }
    }
    
    private var loadingCard: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Analyzing your profile...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 40)
            Spacer()
        }
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var fallbackCard: some View {
        Button(action: { HapticManager.impact(.light); onViewProgram(nil) }) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Explore Programs")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Find the perfect program for your goals")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func smartProgramCard(_ rec: ProgramRecommendation) -> some View {
        Button(action: { HapticManager.impact(.light); onViewProgram(rec.program.id) }) {
            VStack(spacing: 0) {
                // Top Section - Program Info
                HStack(alignment: .top, spacing: 14) {
                    // Program Icon with animated ring
                    ZStack {
                        // Match score ring
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                            .frame(width: 64, height: 64)
                        
                        Circle()
                            .trim(from: 0, to: min(CGFloat(matchScore) / 250.0, 1.0))
                            .stroke(
                                LinearGradient(colors: [matchColor, matchColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 64, height: 64)
                            .rotationEffect(.degrees(-90))
                        
                        // Icon
                        Image(systemName: iconForProgram(rec.program))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(matchColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // Match badge
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                            Text(matchLabel)
                                .font(.caption)
                                .fontWeight(.bold)
                            Text("• \(matchScore) pts")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(matchColor)
                        
                        // Program name
                        Text(rec.program.name)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        // Primary reason
                        if let reason = rec.reasons.first {
                            Text(reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                }
                .padding(16)
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Middle Section - Why This Program
                VStack(alignment: .leading, spacing: 10) {
                    Text("Why This Program")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    // Compatibility indicators
                    HStack(spacing: 12) {
                        compatibilityBadge(
                            icon: "dumbbell.fill",
                            label: "Equipment",
                            status: rec.equipmentCompatibility.rawValue,
                            color: colorForCompatibility(rec.equipmentCompatibility)
                        )
                        
                        compatibilityBadge(
                            icon: "chart.line.uptrend.xyaxis",
                            label: "Difficulty",
                            status: rec.difficultyMatch.rawValue,
                            color: colorForDifficulty(rec.difficultyMatch)
                        )
                        
                        compatibilityBadge(
                            icon: "calendar",
                            label: "Duration",
                            status: "\(rec.program.duration) days",
                            color: .blue
                        )
                    }
                }
                .padding(16)
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Bottom Section - Program Stats & CTA
                HStack(spacing: 12) {
                    // Stats - spread evenly across available space
                    HStack(spacing: 0) {
                        miniStat(icon: "flame.fill", value: "\(rec.program.workoutsPerWeek)", label: "days/wk", color: .orange)
                            .frame(maxWidth: .infinity)
                        miniStat(icon: "clock.fill", value: "~45", label: "min", color: .blue)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // CTA Button
                    HStack(spacing: 6) {
                        Text("View Program")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [matchColor, matchColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
                }
                .padding(16)
            }
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background(
                ZStack {
                    // Depth shadow layers
                    RoundedRectangle(cornerRadius: 20)
                        .fill(matchColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.cardBackground)
                    
                    // Inner highlight
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
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(colors: [matchColor.opacity(colorScheme == .dark ? 0.4 : 0.3), matchColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: matchColor.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(WorkoutDepthButtonStyle())
    }
    
    private func compatibilityBadge(icon: String, label: String, status: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(status)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func miniStat(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func loadRecommendation() {
        guard let user = user else {
            isLoading = false
            return
        }
        
        // Load recommendation in background
        DispatchQueue.global(qos: .userInitiated).async {
            let recs = SmartProgramRecommender.shared.getTopRecommendedPrograms(for: user, limit: 1)
            DispatchQueue.main.async {
                self.recommendation = recs.first
                withAnimation(.easeOut(duration: 0.3)) {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func iconForProgram(_ program: WorkoutProgram) -> String {
        let focusString = program.focus.rawValue.lowercased()
        if focusString.contains("strength") { return "figure.strengthtraining.traditional" }
        if focusString.contains("muscle") || focusString.contains("hyper") { return "figure.arms.open" }
        if focusString.contains("fat") || focusString.contains("loss") { return "flame.fill" }
        if focusString.contains("full") { return "figure.mixed.cardio" }
        if focusString.contains("upper") { return "figure.boxing" }
        if focusString.contains("lower") || focusString.contains("leg") { return "figure.run" }
        if focusString.contains("core") { return "figure.core.training" }
        return "figure.cooldown"
    }
    
    private func colorForCompatibility(_ compat: EquipmentCompatibility) -> Color {
        switch compat {
        case .perfect: return .green
        case .good: return .blue
        case .partial: return .orange
        case .poor: return .red
        }
    }
    
    private func colorForDifficulty(_ match: DifficultyMatch) -> Color {
        switch match {
        case .perfect: return .green
        case .challenging: return .blue
        case .comfortable: return .cyan
        case .tooEasy: return .orange
        case .tooHard: return .red
        }
    }
}

struct ProgramSuggestionCard: View {
    let program: SuggestedProgram
    let userGoal: String
    let userLevel: String
    let action: () -> Void
    
    var body: some View {
        Button(action: { HapticManager.impact(.light); action() }) {
            VStack(alignment: .leading, spacing: 20) {
                // Header with gradient badge
                HStack(alignment: .top, spacing: 16) {
                    // Program icon with gradient
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [program.primaryColor, program.secondaryColor]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: program.primaryColor.opacity(0.4), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: program.icon)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // "Matched for you" badge
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                            Text("Perfect Match")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(program.primaryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(program.primaryColor.opacity(0.12))
                        .cornerRadius(12)
                        
                        Text(program.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                
                // Description
                Text(program.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Focus areas
                VStack(alignment: .leading, spacing: 8) {
                    Text("Program Focus")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack(spacing: 8) {
                        ForEach(program.focusAreas.prefix(3), id: \.self) { focus in
                            Text(focus)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(program.primaryColor.opacity(0.1))
                                .foregroundColor(program.primaryColor)
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Program details row
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(program.primaryColor)
                        Text(program.duration)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(.caption)
                            .foregroundColor(program.primaryColor)
                        Text(program.workoutsPerWeek)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Difficulty badge
                    Text(program.difficulty)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(program.secondaryColor.opacity(0.15))
                        .foregroundColor(program.secondaryColor)
                        .cornerRadius(8)
                }
                
                // Prominent CTA Button
                HStack {
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text(program.callToAction)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [program.primaryColor, program.secondaryColor]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: program.primaryColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Spacer()
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [program.primaryColor.opacity(0.3), program.secondaryColor.opacity(0.3)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: program.primaryColor.opacity(0.15), radius: 15, x: 0, y: 8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct NearAchievementCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let description: String
    let progress: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon and progress
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .padding(16)
        .frame(width: 140)
        .background(Color.cardBackground)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
    }
}

struct WorkoutTabRecentCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let workout: Workout
    
    var body: some View {
        HStack(spacing: 16) {
            // Workout icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
            
            // Workout details
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name ?? "Workout")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    if let date = workout.date {
                        Text(formatDate(date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if workout.duration > 0 {
                        Text("• \(formatDuration(Int(workout.duration)))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // XP earned
            VStack(spacing: 2) {
                Text("+\(Int(workout.xpEarned))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Text("XP")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(16)
        .background(Color.cardBackground)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

struct EmptyRecentActivityCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Recent Activity")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Complete your first workout to see your activity here!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .background(Color.cardBackground)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
    }
}

// MARK: - Next Goals System

enum GoalType {
    case achievement      // Based on achievement progress
    case dailyChallenge   // Complete X workouts today
    case weeklyChallenge  // Complete X workouts this week
    case streakMaintain   // Keep your streak going
    case personalRecord   // Close to a PR
    case muscleBalance    // Train a neglected muscle group
    case levelUp          // Close to leveling up
}

enum GoalAction {
    case startWorkout(focus: String?)  // Start a workout, optionally focused on muscle/type
    case viewAchievements              // Go to achievements page
    case viewProgress                  // Go to progress page
    case none                          // No action, just informational
}

struct NextGoal: Identifiable {
    let id: String
    let type: GoalType
    let title: String
    let subtitle: String        // What you need to do
    let icon: String
    let progress: Double        // 0.0 - 1.0
    let remaining: String       // e.g., "2 more workouts", "15 lbs to go"
    let timeContext: String?    // e.g., "this week", "today", nil
    let accentColor: Color
    let action: GoalAction
    let priority: Int           // Lower = higher priority
    let xpReward: Int?          // Optional XP reward for completion
}

struct NextGoalCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let goal: NextGoal
    let onAction: (GoalAction) -> Void
    
    private var gradientColors: [Color] {
        switch goal.accentColor {
        case .orange: return [.orange, .yellow]
        case .blue: return [.blue, .cyan]
        case .green: return [.green, .teal]
        case .purple: return [.purple, .pink]
        case .red: return [.red, .orange]
        case .yellow: return [.yellow, .orange]
        case .pink: return [.pink, .purple]
        case .mint: return [.mint, .teal]
        case .cyan: return [.cyan, .blue]
        default: return [goal.accentColor, goal.accentColor.opacity(0.7)]
        }
    }
    
    private var typeIcon: String {
        switch goal.type {
        case .dailyChallenge: return "sun.max.fill"
        case .weeklyChallenge: return "calendar.badge.clock"
        case .streakMaintain: return "flame.fill"
        case .personalRecord: return "trophy.fill"
        case .muscleBalance: return "figure.strengthtraining.traditional"
        case .levelUp: return "arrow.up.circle.fill"
        case .achievement: return goal.icon
        }
    }
    
    var body: some View {
        Button(action: { HapticManager.impact(.light); onAction(goal.action) }) {
            VStack(spacing: 10) {
                // Icon with progress ring
                ZStack {
                    Circle()
                        .stroke(goal.accentColor.opacity(0.15), lineWidth: 4)
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .trim(from: 0, to: goal.progress)
                        .stroke(
                            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: goal.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                
                // Title & subtitle
                VStack(spacing: 3) {
                    Text(goal.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text(goal.remaining)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                
                // XP badge or progress
                if let xp = goal.xpReward {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("+\(xp) XP")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(gradientColors[0])
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(gradientColors[0].opacity(0.15))
                    )
                } else {
                    Text("\(Int(goal.progress * 100))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        )
                }
            }
            .frame(width: 160, height: 140)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored based on gradient
                    RoundedRectangle(cornerRadius: 20)
                        .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color.darkCardBackground, Color.darkSurface]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16)
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
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    gradientColors[0].opacity(colorScheme == .dark ? 0.4 : 0.3),
                                    gradientColors[1].opacity(colorScheme == .dark ? 0.3 : 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(WorkoutDepthButtonStyle())
    }
}

struct EmptyNextGoalsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.green.opacity(0.2), .teal.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 3) {
                Text("All Done!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Goals complete")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            
            // Celebratory badge
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                Text("Great job!")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.15))
            )
        }
        .frame(width: 160, height: 140)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - colored based on gradient
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.green.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.darkCardBackground, Color.darkSurface]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 16)
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
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                Color.teal.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Floating GO Button

struct FloatingGoButton: View {
    let action: () -> Void
    var primaryColor: Color = Color(red: 0.2, green: 0.7, blue: 0.3)
    var secondaryColor: Color = Color(red: 0.15, green: 0.55, blue: 0.85)
    
    @State private var isPressed = false
    @State private var pulseAnimation = false
    
    // Computed gradient colors
    private var gradientColors: [Color] {
        [primaryColor, secondaryColor]
    }
    
    private var glowColors: [Color] {
        [primaryColor.opacity(0.3), secondaryColor.opacity(0.2)]
    }
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            
            // Execute provided action
            action()
        }) {
            ZStack {
                // Solid white background circle (largest - ensures nothing shows through)
                Circle()
                    .fill(Color.white)
                    .frame(width: 82, height: 82)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                
                // Main gradient button (fully opaque, on top of white)
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)
                    .shadow(color: primaryColor.opacity(0.4), radius: isPressed ? 5 : 15, x: 0, y: isPressed ? 2 : 8)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                
                // GO! Text
                Text("GO!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Active Program Progress Card (Redesigned)
struct ActiveProgramProgressCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let program: FullCloudProgram
    let progress: UserActiveProgram
    let totalWorkouts: Int
    let onTap: () -> Void
    
    @State private var animateProgress = false
    
    private var programColor: Color {
        program.program.programColor
    }
    
    private var completionPercentage: Double {
        let totalDays = program.program.durationDays
        let completedDays = progress.completedDays.count
        return totalDays > 0 ? Double(completedDays) / Double(totalDays) : 0
    }
    
    private var daysRemaining: Int {
        max(0, program.program.durationDays - progress.completedDays.count)
    }
    
    private var currentStreak: Int {
        var streak = 0
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in (0..<7).reversed() {
            if let checkDate = calendar.date(byAdding: .day, value: -i, to: today) {
                let dayOfProgram = calendar.dateComponents([.day], from: calendar.startOfDay(for: dateFromString(progress.startDate) ?? Date()), to: checkDate).day ?? 0
                if progress.completedDays.contains(dayOfProgram + 1) {
                    streak += 1
                } else if i < 6 {
                    break
                }
            }
        }
        return max(streak, progress.completedDays.count > 0 ? 1 : 0)
    }
    
    private func dateFromString(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)
    }
    
    private var statusLabel: String {
        let percentage = completionPercentage * 100
        if percentage >= 90 { return "Final Push" }
        if percentage >= 75 { return "Almost There" }
        if percentage >= 50 { return "Halfway" }
        if percentage >= 25 { return "Building" }
        if percentage > 0 { return "Started" }
        return "Ready"
    }
    
    private var statusColor: Color {
        let percentage = completionPercentage * 100
        if percentage >= 75 { return .green }
        if percentage >= 50 { return .blue }
        if percentage >= 25 { return .orange }
        return programColor
    }
    
    var body: some View {
        cardContent
            .buttonStyle(WorkoutDepthButtonStyle())
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                    animateProgress = true
                }
            }
    }
    
    private var cardContent: some View {
        Button(action: { HapticManager.impact(.light); onTap() }) {
            VStack(spacing: 0) {
                // Top Section - Program Info & Progress Ring
                HStack(alignment: .top, spacing: 14) {
                    // Animated Progress Ring
                    ZStack {
                        // Track
                        Circle()
                            .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                            .frame(width: 68, height: 68)
                        
                        // Progress
                        Circle()
                            .trim(from: 0, to: animateProgress ? completionPercentage : 0)
                            .stroke(
                                LinearGradient(colors: [programColor, programColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: 68, height: 68)
                            .rotationEffect(.degrees(-90))
                        
                        // Center percentage
                        VStack(spacing: -2) {
                            Text("\(Int(completionPercentage * 100))")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(programColor)
                            Text("%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // Status badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(statusLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(statusColor)
                        
                        // Program name
                        Text(program.program.name)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        // Day progress
                        Text("Day \(progress.currentDay) of \(program.program.durationDays)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
                
                // Thin divider
                Rectangle()
                    .fill(Color.gray.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                
                // Stats Grid - Clean 3-column layout
                HStack(spacing: 0) {
                    // Days Done
                    statCell(
                        value: "\(progress.completedDays.count)",
                        label: "Done",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    // Vertical divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 1, height: 44)
                    
                    // Streak
                    statCell(
                        value: "\(currentStreak)",
                        label: "Streak",
                        icon: "flame.fill",
                        color: .orange
                    )
                    
                    // Vertical divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 1, height: 44)
                    
                    // Days Left
                    statCell(
                        value: "\(daysRemaining)",
                        label: "Left",
                        icon: "calendar",
                        color: .blue
                    )
                }
                .padding(.vertical, 14)
                
                // Continue Button - Clean CTA
                HStack(spacing: 8) {
                    Text("Continue Today's Workout")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [programColor, programColor.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
                )
            }
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background(
                ZStack {
                    // Depth shadows
                    RoundedRectangle(cornerRadius: 20)
                        .fill(programColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.cardBackground)
                    
                    // Inner highlight
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
                            LinearGradient(colors: [programColor.opacity(colorScheme == .dark ? 0.4 : 0.25), programColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 12, x: 0, y: 6)
            .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 20, x: 0, y: 10)
        }
    }
    
    // Clean stat cell component
    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Progress Stat Item
struct ProgressStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Smart Insights Card
struct SmartInsightsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let workouts: [Workout]
    let todayExercises: [String]
    let onViewProgram: () -> Void
    @ObservedObject private var cloudProgramService = CloudProgramService.shared
    
    // MARK: - Muscle Recovery Analysis
    private var muscleLastWorked: [String: Date] {
        var lastWorked: [String: Date] = [:]
        
        for workout in workouts {
            guard let date = workout.date,
                  let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            
            for workoutExercise in exercises {
                // Use safeMuscleGroups for nil-safety
                for muscle in workoutExercise.safeMuscleGroups {
                    if lastWorked[muscle] == nil || date > lastWorked[muscle]! {
                        lastWorked[muscle] = date
                    }
                }
            }
        }
        return lastWorked
    }
    
    private var muscleRecoveryStatus: [(muscle: String, daysRested: Int, status: RecoveryStatus)] {
        let calendar = Calendar.current
        let now = Date()
        
        return muscleLastWorked.map { muscle, lastDate in
            let days = calendar.dateComponents([.day], from: lastDate, to: now).day ?? 0
            let status: RecoveryStatus
            if days <= 1 {
                status = .fatigued
            } else if days <= 2 {
                status = .recovering
            } else if days <= 4 {
                status = .ready
            } else {
                status = .fullyRested
            }
            return (muscle: muscle, daysRested: days, status: status)
        }
        .sorted { $0.daysRested < $1.daysRested }
    }
    
    private var musclesToRest: [String] {
        muscleRecoveryStatus.filter { $0.status == .fatigued }.map { $0.muscle.capitalized }
    }
    
    private var musclesReadyToTrain: [String] {
        muscleRecoveryStatus.filter { $0.status == .ready || $0.status == .fullyRested }.map { $0.muscle.capitalized }
    }
    
    // MARK: - Lift Heavier Suggestions
    private var liftHeavierSuggestions: [(exercise: String, currentMax: Double, suggestion: String)] {
        var suggestions: [(exercise: String, currentMax: Double, suggestion: String)] = []
        var exerciseMaxes: [String: (weight: Double, reps: Int, date: Date)] = [:]
        
        // Find max weight for each exercise in last 30 days
        let recentWorkouts = workouts.filter {
            guard let date = $0.date else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        }
        
        for workout in recentWorkouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for workoutExercise in exercises {
                let exerciseName = workoutExercise.safeDisplayName
                guard exerciseName != "Loading...",
                      let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else { continue }
                
                for set in sets where set.isCompleted && set.weight > 0 {
                    if let current = exerciseMaxes[exerciseName] {
                        if set.weight > current.weight {
                            exerciseMaxes[exerciseName] = (weight: set.weight, reps: Int(set.reps), date: workout.date ?? Date())
                        }
                    } else {
                        exerciseMaxes[exerciseName] = (weight: set.weight, reps: Int(set.reps), date: workout.date ?? Date())
                    }
                }
            }
        }
        
        // Suggest 5-10% increase for exercises not progressed recently
        for (exercise, data) in exerciseMaxes {
            let daysSinceMax = Calendar.current.dateComponents([.day], from: data.date, to: Date()).day ?? 0
            if daysSinceMax > 7 && data.reps >= 8 {
                let increment = max(5, Int(data.weight * 0.05))
                suggestions.append((
                    exercise: exercise,
                    currentMax: data.weight,
                    suggestion: "Try \(Int(data.weight) + increment) lbs"
                ))
            }
        }
        
        return suggestions.prefix(3).map { $0 }
    }
    
    // MARK: - Recent PRs
    private var recentPRs: [(exercise: String, weight: Double, reps: Int, date: Date)] {
        var prs: [(exercise: String, weight: Double, reps: Int, date: Date)] = []
        var bestSets: [String: (weight: Double, reps: Int)] = [:]
        
        let sortedWorkouts = workouts.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        for workout in sortedWorkouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for workoutExercise in exercises {
                let exerciseName = workoutExercise.safeDisplayName
                guard exerciseName != "Loading...",
                      let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else { continue }
                
                for set in sets where set.isCompleted {
                    let currentBest = bestSets[exerciseName]
                    let isNewPR = currentBest == nil || set.weight > currentBest!.weight || (set.weight == currentBest!.weight && set.reps > currentBest!.reps)
                    
                    if isNewPR {
                        bestSets[exerciseName] = (weight: set.weight, reps: Int(set.reps))
                        if let date = workout.date, date > Calendar.current.date(byAdding: .day, value: -14, to: Date())! {
                            prs.removeAll { $0.exercise == exerciseName }
                            prs.append((exercise: exerciseName, weight: set.weight, reps: Int(set.reps), date: date))
                        }
                    }
                }
            }
        }
        
        return prs.sorted { $0.date > $1.date }.prefix(3).map { $0 }
    }
    
    // MARK: - Performance Stats
    private var workoutsThisWeek: Int {
        workouts.filter {
            guard let date = $0.date else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }.count
    }
    
    private var totalVolumeThisWeek: Double {
        let recentWorkouts = workouts.filter {
            guard let date = $0.date else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }
        
        return recentWorkouts.reduce(0.0) { total, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return total }
            return total + exercises.reduce(0.0) { exerciseTotal, workoutExercise in
                guard let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else { return exerciseTotal }
                return exerciseTotal + sets.filter { $0.isCompleted }.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
            }
        }
    }
    
    /// Smart streak - uses centralized UserManager logic that respects rest days
    private var currentStreak: Int {
        return Int(UserManager.shared.currentUser?.currentStreak ?? 0)
    }
    
    // MARK: - Training Score
    private var trainingScore: Int {
        var score = 0
        
        // Consistency (max 30 points)
        if workoutsThisWeek >= 5 { score += 30 }
        else if workoutsThisWeek >= 4 { score += 25 }
        else if workoutsThisWeek >= 3 { score += 20 }
        else if workoutsThisWeek >= 2 { score += 10 }
        else if workoutsThisWeek >= 1 { score += 5 }
        
        // PRs (max 25 points)
        score += min(recentPRs.count * 8, 25)
        
        // Volume progress (max 25 points)
        if totalVolumeThisWeek > 50000 { score += 25 }
        else if totalVolumeThisWeek > 30000 { score += 20 }
        else if totalVolumeThisWeek > 15000 { score += 15 }
        else if totalVolumeThisWeek > 5000 { score += 10 }
        
        // Muscle balance (max 20 points)
        let muscleVariety = Set(muscleRecoveryStatus.map { $0.muscle }).count
        if muscleVariety >= 6 { score += 20 }
        else if muscleVariety >= 4 { score += 15 }
        else if muscleVariety >= 2 { score += 10 }
        
        return min(score, 100)
    }
    
    private var scoreColor: Color {
        if trainingScore >= 80 { return .green }
        else if trainingScore >= 60 { return .yellow }
        else if trainingScore >= 40 { return .orange }
        else { return .red }
    }
    
    // MARK: - Smart Insights
    private var positiveInsights: [TrainingInsight] {
        var insights: [TrainingInsight] = []
        
        if !recentPRs.isEmpty {
            insights.append(TrainingInsight(
                icon: "trophy.fill",
                text: "\(recentPRs.count) new PR\(recentPRs.count > 1 ? "s" : "") this week! Keep pushing! 🔥",
                color: .yellow
            ))
        }
        
        if workoutsThisWeek >= 4 {
            insights.append(TrainingInsight(
                icon: "checkmark.circle.fill",
                text: "Great consistency – \(workoutsThisWeek) workouts this week!",
                color: .green
            ))
        }
        
        if currentStreak >= 3 {
            insights.append(TrainingInsight(
                icon: "flame.fill",
                text: "\(currentStreak)-day training streak! Don't break it!",
                color: .orange
            ))
        }
        
        if !musclesReadyToTrain.isEmpty && musclesReadyToTrain.count >= 3 {
            insights.append(TrainingInsight(
                icon: "bolt.fill",
                text: "Multiple muscle groups fully recovered and ready!",
                color: .green
            ))
        }
        
        return insights.prefix(2).map { $0 }
    }
    
    private var actionableInsights: [TrainingInsight] {
        var insights: [TrainingInsight] = []
        
        if !musclesToRest.isEmpty {
            let muscleList = musclesToRest.prefix(2).joined(separator: ", ")
            insights.append(TrainingInsight(
                icon: "bed.double.fill",
                text: "Rest \(muscleList) – worked recently. Try other muscles today.",
                color: .blue
            ))
        }
        
        if let suggestion = liftHeavierSuggestions.first {
            insights.append(TrainingInsight(
                icon: "arrow.up.circle.fill",
                text: "\(suggestion.exercise): Ready to go heavier! \(suggestion.suggestion)",
                color: .purple
            ))
        }
        
        if workoutsThisWeek < 3 {
            insights.append(TrainingInsight(
                icon: "calendar.badge.plus",
                text: "Only \(workoutsThisWeek) workout\(workoutsThisWeek == 1 ? "" : "s") this week. Aim for 3-4!",
                color: .orange
            ))
        }
        
        if recentPRs.isEmpty && workoutsThisWeek >= 2 {
            insights.append(TrainingInsight(
                icon: "sparkles",
                text: "No PRs lately – try progressive overload this session!",
                color: .purple
            ))
        }
        
        return insights.prefix(2).map { $0 }
    }
    
    private var dailyTip: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        
        // Weekend tips
        if dayOfWeek == 1 || dayOfWeek == 7 {
            let tips = [
                "💡 Weekends are great for longer sessions – take your time!",
                "💡 Use rest days for stretching and mobility work.",
                "💡 Meal prep on weekends sets you up for the week.",
            ]
            return tips.randomElement() ?? tips[0]
        }
        
        if hour < 12 {
            let tips = [
                "💡 Morning workouts boost metabolism all day long.",
                "💡 Don't skip warm-up – 5 mins prevents injuries.",
                "💡 High-protein breakfast fuels better performance.",
            ]
            return tips.randomElement() ?? tips[0]
        } else if hour < 17 {
            let tips = [
                "💡 Afternoon is peak strength time for most people.",
                "💡 Stay hydrated – performance drops 10% when dehydrated.",
                "💡 Mind-muscle connection matters more than weight.",
            ]
            return tips.randomElement() ?? tips[0]
        } else {
            let tips = [
                "💡 Evening workouts can improve sleep quality.",
                "💡 Don't train to failure every set – leave 1-2 reps.",
                "💡 Post-workout protein within 2 hours maximizes gains.",
            ]
            return tips.randomElement() ?? tips[0]
        }
    }
    
    private var greeting: String {
        if trainingScore >= 80 {
            return "Outstanding performance! 🏆"
        } else if trainingScore >= 60 {
            return "Solid progress this week! 💪"
        } else if workoutsThisWeek == 0 {
            return "Ready to get back at it? 🎯"
        } else {
            return "Keep building momentum! 🚀"
        }
    }
    
    private func getScoreDescription() -> String {
        if trainingScore >= 80 {
            return "Top performer this week"
        } else if trainingScore >= 60 {
            return "On track for your goals"
        } else if trainingScore >= 40 {
            return "Room for improvement"
        } else {
            return "Let's build consistency"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Greeting header with score
            HStack(alignment: .center) {
                Text(greeting)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Compact score badge
                HStack(spacing: 4) {
                    Text("\(trainingScore)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text("pts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(scoreColor.opacity(0.12))
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            // Quick Stats Row
            HStack(spacing: 0) {
                QuickTrainingStat(
                    value: "\(workoutsThisWeek)",
                    label: "This Week",
                    icon: "flame.fill",
                    color: workoutsThisWeek >= 3 ? .green : .gray
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 32)
                
                QuickTrainingStat(
                    value: formatVolume(totalVolumeThisWeek),
                    label: "Volume",
                    icon: "scalemass.fill",
                    color: .blue
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 32)
                
                QuickTrainingStat(
                    value: "\(recentPRs.count)",
                    label: "PRs",
                    icon: "trophy.fill",
                    color: recentPRs.isEmpty ? .gray : .yellow
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 32)
                
                QuickTrainingStat(
                    value: "\(currentStreak)",
                    label: "Streak",
                    icon: "bolt.fill",
                    color: currentStreak >= 3 ? .orange : .gray
                )
            }
            .padding(.vertical, 10)
            
            // Insights as stacked text with icons
            if !positiveInsights.isEmpty || !actionableInsights.isEmpty {
                Divider()
                    .padding(.horizontal, 16)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Positive insights
                    ForEach(positiveInsights.prefix(2)) { insight in
                        TrainingInsightRow(insight: insight)
                    }
                    
                    // Actionable insights
                    ForEach(actionableInsights.prefix(2)) { insight in
                        TrainingInsightRow(insight: insight)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            
            // Muscle Recovery Status (compact horizontal scroll)
            if !muscleRecoveryStatus.isEmpty {
                Divider()
                    .padding(.horizontal, 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(muscleRecoveryStatus.prefix(5), id: \.muscle) { item in
                            MuscleRecoveryBadge(muscle: item.muscle, status: item.status, daysRested: item.daysRested)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 10)
            }
            
            // View Program Link - subtle, inline style
            Divider()
                .padding(.horizontal, 16)
            
            Button(action: { HapticManager.impact(.light); onViewProgram() }) {
                HStack(spacing: 10) {
                    // Program icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [scoreColor.opacity(0.15), scoreColor.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(scoreColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("View Program")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(dailyTip.replacingOccurrences(of: "💡 ", with: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - colored based on score
                RoundedRectangle(cornerRadius: 24)
                    .fill(scoreColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .offset(y: 10)
                    .blur(radius: 6)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06))
                    .offset(y: 5)
                
                // Main card background
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.darkCardBackground, Color.darkSurface]
                                : [Color.white, Color.white.opacity(0.97)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.03), Color.clear]
                                : [Color.white, Color.white.opacity(0.6), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Colored accent border based on score
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                scoreColor.opacity(colorScheme == .dark ? 0.35 : 0.25),
                                scoreColor.opacity(colorScheme == .dark ? 0.2 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 15, x: 0, y: 8)
        .shadow(color: scoreColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 25, x: 0, y: 12)
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000000 {
            return String(format: "%.1fM", volume / 1000000)
        } else if volume >= 1000 {
            return String(format: "%.0fK", volume / 1000)
        } else {
            return String(format: "%.0f", volume)
        }
    }
}

// MARK: - Recovery Status
enum RecoveryStatus {
    case fatigued, recovering, ready, fullyRested
    
    var color: Color {
        switch self {
        case .fatigued: return .red
        case .recovering: return .orange
        case .ready: return .green
        case .fullyRested: return .blue
        }
    }
    
    var label: String {
        switch self {
        case .fatigued: return "Rest"
        case .recovering: return "Recovering"
        case .ready: return "Ready"
        case .fullyRested: return "Fresh"
        }
    }
}

// MARK: - Training Insight Model
struct TrainingInsight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let color: Color
}

// MARK: - Training Insight Row (Floating text with icon)
struct TrainingInsightRow: View {
    let insight: TrainingInsight
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: insight.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(insight.color)
                .frame(width: 20)
            
            Text(insight.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

// MARK: - Insight Chip (compact horizontal display)

struct InsightChip: View {
    let insight: TrainingInsight
    let tint: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: insight.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
            
            Text(cleanInsightText(insight.text))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }
    
    // Clean up the text - remove emojis and shorten
    private func cleanInsightText(_ text: String) -> String {
        var cleaned = text
        // Remove common emojis
        let emojis = ["🔥", "💪", "🎯", "🚀", "🏆", "💡", "😊", "⚡️"]
        for emoji in emojis {
            cleaned = cleaned.replacingOccurrences(of: emoji, with: "")
        }
        // Trim and limit length
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.count > 35 {
            let index = cleaned.index(cleaned.startIndex, offsetBy: 32)
            cleaned = String(cleaned[..<index]) + "..."
        }
        return cleaned
    }
}

// MARK: - Muscle Recovery Badge
struct MuscleRecoveryBadge: View {
    let muscle: String
    let status: RecoveryStatus
    let daysRested: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(status.color.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Text("\(daysRested)d")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(status.color)
                )
            
            Text(muscle.capitalized)
                .font(.system(size: 10))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(status.label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(status.color)
        }
        .frame(width: 60)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(status.color.opacity(0.08))
        )
    }
}

// MARK: - Quick Training Stat
struct QuickTrainingStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact Stat (for sleeker widget)
struct CompactStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Muscle Progress Bar
struct MuscleProgressBar: View {
    let muscle: String
    let percentage: Double
    let count: Int
    
    private var muscleColor: Color {
        switch muscle.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "shoulders": return .orange
        case "biceps", "triceps", "arms": return .purple
        case "legs", "quads", "hamstrings", "glutes": return .green
        case "core", "abs": return .yellow
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Text(muscle.capitalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 70, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(colors: [muscleColor, muscleColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geometry.size.width * min(percentage / 40, 1.0)) // 40% = full bar
                }
            }
            .frame(height: 8)
            
            Text("\(Int(percentage))%")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
    }
}

// MARK: - Insight Stat Cell
struct InsightStatCell: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Workout Tab Program Card
struct WorkoutTabProgramCard: View {
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
                    .font(.system(size: 16, weight: .bold))
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
                Text("Start Program")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(programColor.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    WorkoutTabView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .environmentObject(UserManager())
        .environmentObject(WorkoutManager.shared)
}
