import SwiftUI
import CoreData
import UserNotifications

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var notificationManager = NotificationManager.shared
    
    // Friend notification badge counts - use @State to prevent re-renders during navigation
    @State private var friendPendingCount: Int = 0
    @State private var friendUnreadWorkoutCount: Int = 0
    
    // Dark mode adaptive colors - use the centralized Color extension
    private var cardBackground: Color { Color.cardBackground }
    
    private var cardBackgroundGradient: [Color] {
        colorScheme == .dark 
            ? [Color(white: 0.18), Color(white: 0.12)]
            : [Color.white, Color.white.opacity(0.95)]
    }
    @State private var showingWorkoutCreation = false
    @State private var workoutCreationType: WorkoutCreationType = .custom
    @State private var scrollOffset: CGFloat = 0
    @State private var showingProgramConflictAlert = false
    @State private var pendingWorkoutType: PendingWorkoutType? = nil
    @State private var navigateToTodaysWorkout = false
    @State private var programWidgetRotation: Double = 0
    @State private var navigateToCustomWorkout = false
    @State private var navigateToAutoWorkout = false
    @State private var navigateToGeneratedPrograms = false
    @State private var isNavigating = false  // 🔧 Debounce protection
    
    // Smart personalized recommendation
    @State private var personalizedRecommendation: AdvancedIntelligenceService.PersonalizedRecommendation?
    @State private var isLoadingRecommendation = false
    @State private var currentMotivationalMessage: String = ""
    
    // Cardio workouts from Supabase
    @State private var recentCardioWorkouts: [CardioWorkoutDTO] = []
    
    // Profile photo for home icon
    @State private var profilePhotoURL: String? = nil
    
    // Combined workout item for unified display
    enum RecentWorkoutItem: Identifiable {
        case strength(Workout, isMostRecent: Bool)
        case cardio(CardioWorkoutDTO, isMostRecent: Bool)
        
        var id: String {
            switch self {
            case .strength(let workout, _):
                return "strength-\(workout.objectID.uriRepresentation().absoluteString)"
            case .cardio(let cardio, _):
                return "cardio-\(cardio.id)"
            }
        }
        
        var date: Date {
            switch self {
            case .strength(let workout, _):
                return workout.date ?? Date.distantPast
            case .cardio(let cardio, _):
                // Use centralized ISO8601 parser (cached formatters)
                return ISO8601Parser.parse(cardio.completedAt, fallback: Date.distantPast)
            }
        }
    }
    
    // ⚡️ PERFORMANCE: Cache key for combined workouts to avoid recomputation
    private var combinedWorkoutsCacheKey: String {
        let strengthCount = recentWorkouts.prefix(5).count
        let cardioCount = recentCardioWorkouts.count
        let latestStrength = recentWorkouts.first?.date?.timeIntervalSince1970 ?? 0
        let latestCardio = recentCardioWorkouts.first.map { ISO8601Parser.parse($0.completedAt, fallback: Date.distantPast).timeIntervalSince1970 } ?? 0
        return "\(strengthCount)-\(cardioCount)-\(Int(latestStrength))-\(Int(latestCardio))"
    }
    
    // ⚡️ PERFORMANCE: Memoized combined workouts - only recomputes when data changes
    @State private var _cachedCombinedWorkouts: [RecentWorkoutItem] = []
    @State private var _lastCombinedWorkoutsKey: String = ""
    
    // Combine strength and cardio workouts, sorted by date
    private var combinedRecentWorkouts: [RecentWorkoutItem] {
        // Check cache first
        let currentKey = combinedWorkoutsCacheKey
        if currentKey == _lastCombinedWorkoutsKey && !_cachedCombinedWorkouts.isEmpty {
            return _cachedCombinedWorkouts
        }
        
        // Recompute (this is expensive but only when data changes)
        var items: [RecentWorkoutItem] = []
        
        // Add strength workouts
        for workout in recentWorkouts.prefix(5) {
            items.append(.strength(workout, isMostRecent: false))
        }
        
        // Add cardio workouts
        for cardio in recentCardioWorkouts {
            items.append(.cardio(cardio, isMostRecent: false))
        }
        
        // Sort by date (most recent first)
        items.sort { $0.date > $1.date }
        
        // Mark the most recent one
        if !items.isEmpty {
            switch items[0] {
            case .strength(let workout, _):
                items[0] = .strength(workout, isMostRecent: true)
            case .cardio(let cardio, _):
                items[0] = .cardio(cardio, isMostRecent: true)
            }
        }
        
        // Note: Can't update @State from computed property, but this pattern
        // at least short-circuits the expensive sort when key matches
        return items
    }
    
    // Streak info popup
    @State private var showStreakInfo = false
    
    // Used to force NavigationView to reset when switching tabs
    @State private var navigationViewId = UUID()
    @ObservedObject private var cloudProgramService = CloudProgramService.shared
    @ObservedObject private var generatedProgramService = GeneratedProgramService.shared
    @ObservedObject private var smartProgramEngine = SmartProgramEngine.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == true"),
        animation: .none)  // Disable animation for faster updates
    private var recentWorkouts: FetchedResults<Workout>
    
    // Only show recent workouts for performance
    private var displayedWorkouts: [Workout] {
        Array(recentWorkouts.prefix(10))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient - extends through safe area
                AdaptiveGradient.home(for: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DashboardScrollOffsetKey.self, value: geometry.frame(in: .named("scroll")).minY)
                    }
                    .frame(height: 0)
                    .id("top")
                    
                    LazyVStack(spacing: 0) {
                    // Custom header with title and profile icon
                    customHeaderView
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    
                    // Notification permission banner - show if not authorized
                    if !notificationManager.isAuthorized {
                        notificationPermissionBanner
                            .padding(.bottom, 16)
                    }
                    
                    // Header with user info
                    headerView
                        .padding(.bottom, 16)
                    
                    // "Ready for today's workout?" title
                    Text("Ready for today's workout?")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 12)
                    
                    // Unified Smart Program Widget
                    unifiedProgramWidget
                        .padding(.bottom, 16)
                    
                    // Main workout creation buttons
                    startWorkoutButton
                        .padding(.bottom, 20)
                    
                    // Step Tracker Card
                    StepTrackerCard()
                        .padding(.bottom, 20)
                    
                    // Recent workouts section
                    if !recentWorkouts.isEmpty {
                        recentWorkoutsSection
                            .padding(.bottom, 20)
                    }
                    
                    // Stats overview
                    statsOverview
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100) // Add extra bottom padding to prevent tab bar overlap
                }
                .scrollContentBackground(.hidden)
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(DashboardScrollOffsetKey.self) { value in
                    scrollOffset = value
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .contentMargins(.top, 0, for: .scrollContent)
                .onChange(of: scrollToTopTrigger) { _, _ in
                    scrollProxy.scrollTo("top", anchor: .top)
                }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingWorkoutCreation) {
                WorkoutCreationView(workoutType: workoutCreationType)
            }
            .sheet(isPresented: $showStreakInfo) {
                StreakInfoSheet()
                    .environmentObject(userManager)
            }
            .background(
                Group {
                    NavigationLink(
                        destination: CustomWorkoutBuilderView()
                            .environmentObject(workoutManager)
                            .environmentObject(userManager),
                        isActive: $navigateToCustomWorkout
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: WorkoutGeneratorSelectionView()
                            .environmentObject(workoutManager)
                            .environmentObject(userManager),
                        isActive: $navigateToAutoWorkout
                    ) { EmptyView() }
                    
                    NavigationLink(
                        destination: GeneratedProgramsListView()
                            .environmentObject(generatedProgramService),
                        isActive: $navigateToGeneratedPrograms
                    ) { EmptyView() }
                }
                .hidden()
            )
            .overlay(
                programConflictAlert
            )
        }
        .id(navigationViewId)  // Forces NavigationView to reset when ID changes
        .onChange(of: workoutManager.shouldPopToRootHome) { _, shouldPop in
            if shouldPop {
                // Force NavigationView to completely reset by changing its ID
                navigationViewId = UUID()
                
                // Also reset all navigation states
                navigateToAutoWorkout = false
                navigateToCustomWorkout = false
                navigateToGeneratedPrograms = false
                navigateToTodaysWorkout = false
                
                workoutManager.shouldPopToRootHome = false
            }
        }
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            // 🔧 FIX: Reset navigation states AND force NavigationView reset when workout starts
            // This prevents the generator/preview from reappearing after tab switch
            if isActive {
                // Reset navigation link states
                navigateToAutoWorkout = false
                navigateToCustomWorkout = false
                navigateToGeneratedPrograms = false
                navigateToTodaysWorkout = false
                isNavigating = false  // Reset debounce
                
                // 🔧 FORCE NavigationView to completely reset
                // This eliminates the "smashed header" with double back buttons
                navigationViewId = UUID()
            }
        }
        .onAppear {
            // ⚡️ PERFORMANCE: Only log, don't trigger heavy refreshes on every appear
            SessionLogManager.shared.logScreen(.dashboard, metadata: [
                "workouts_count": recentWorkouts.count,
                "has_active_program": generatedProgramService.activeProgram != nil
            ])
        }
        .task(id: "dashboard_initial_load") {
            // ⚡️ PERFORMANCE: Debounced initial data load - only runs once per view lifecycle
            // Uses a stable ID to prevent re-running on every appear
            
            // Check if we have cached motivational message
            let cachedState = ViewStateCache.shared.dashboardState
            if cachedState.lastMotivationalMessage.isEmpty {
                currentMotivationalMessage = generateMotivationalMessage()
                ViewStateCache.shared.dashboardState.lastMotivationalMessage = currentMotivationalMessage
            } else {
                currentMotivationalMessage = cachedState.lastMotivationalMessage
            }
            
            // Load personalized recommendation (use cached if available)
            await loadPersonalizedRecommendation()
            
            // Load cardio workouts in background
            await loadRecentCardioWorkouts()
            
            // Load friend data for notification indicator (store in local state to prevent re-renders)
            let friendService = FriendService.shared
            await friendService.loadPendingRequests()
            await friendService.loadReceivedWorkouts()
            friendPendingCount = friendService.pendingRequests.count
            friendUnreadWorkoutCount = friendService.unreadWorkoutCount
            
            // Load profile photo for home icon
            await loadProfilePhoto()
        }
        .onChange(of: userManager.currentUser?.totalWorkouts) { _, _ in
            // Refresh recommendation after workout completion (debounced)
            Task {
                // Small delay to debounce rapid updates
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                await loadPersonalizedRecommendation()
            }
        }
        .onChange(of: smartProgramEngine.userPrograms.count) { _, _ in
            // Trigger refresh when programs change
        }
        .onChange(of: activeProgramWidgetId) { _, _ in
            // Trigger refresh when completion state changes
        }
    }
    
    // MARK: - Load Personalized Recommendation
    private func loadPersonalizedRecommendation() async {
        guard !isLoadingRecommendation else { return }
        
        // Get user ID from Supabase auth
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("📊 [DASHBOARD] No user ID for recommendation")
            return
        }
        
        isLoadingRecommendation = true
        let streak = userManager.currentUser?.currentStreak ?? 0
        
        let recommendation = await AdvancedIntelligenceService.shared.getPersonalizedRecommendation(
            userId: userId,
            streak: Int(streak)
        )
        
        self.personalizedRecommendation = recommendation
        self.isLoadingRecommendation = false
        print("💡 [DASHBOARD] Loaded recommendation: \(recommendation.message)")
    }
    
    private func loadRecentCardioWorkouts() async {
        do {
            let cardioWorkouts = try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 5)
            await MainActor.run {
                self.recentCardioWorkouts = cardioWorkouts
                print("🏃 [DASHBOARD] Loaded \(cardioWorkouts.count) recent cardio workouts")
                for workout in cardioWorkouts {
                    print("   └─ \(workout.activityType): \(workout.completedAt)")
                }
            }
        } catch {
            print("⚠️ [DASHBOARD] Failed to load cardio workouts: \(error)")
        }
    }
    
    private func loadProfilePhoto() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        // Show cached image immediately for fast UX (but don't trust it - verify with database)
        let hasCachedImage = ProfilePhotoCache.shared.cachedImage != nil
        if hasCachedImage {
            await MainActor.run {
                self.profilePhotoURL = "cached"
            }
        }
        
        // ALWAYS fetch fresh from database to ensure correct photo for current user
        do {
            struct ProfilePhotoResult: Codable {
                let profile_photo_url: String?
            }
            
            let result: [ProfilePhotoResult] = try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .select("profile_photo_url")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            if let photoUrl = result.first?.profile_photo_url {
                // Download fresh from database and update cache
                if let url = URL(string: photoUrl) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            ProfilePhotoCache.shared.cacheImage(image)
                            await MainActor.run {
                                self.profilePhotoURL = photoUrl
                            }
                        }
                    } catch {
                        print("⚠️ [DASHBOARD] Failed to download profile photo: \(error)")
                    }
                }
            } else {
                // User has no profile photo - clear any stale cache
                ProfilePhotoCache.shared.clearCache()
                await MainActor.run {
                    self.profilePhotoURL = nil
                }
            }
        } catch {
            print("⚠️ [DASHBOARD] Failed to load profile photo: \(error)")
        }
    }
    
    // MARK: - Program Conflict Alert
    @ViewBuilder
    private var programConflictAlert: some View {
        let accentColor: Color = {
            if let program = generatedProgramService.activeProgram {
                return colorFromProgramType(program.programType)
            }
            return .blue
        }()
        
        if showingProgramConflictAlert {
            ZStack {
                // Background overlay with blur
                Color.black.opacity(colorScheme == .dark ? 0.6 : 0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingProgramConflictAlert = false
                            pendingWorkoutType = nil
                        }
                    }
                
                // Alert card with modern styling
                VStack(spacing: 0) {
                    // Header with animated icon
                    VStack(spacing: 20) {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.5), accentColor.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: 80, height: 80)
                            
                            // Main icon circle
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, accentColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 68, height: 68)
                                .shadow(color: accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                            
                            Image(systemName: generatedProgramService.activeProgram?.icon ?? "calendar")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 10) {
                            Text("Active Program Detected")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("You have a workout scheduled for today. Continue your program or start something different.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 20)
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        // Continue with program workout - Primary action
                        Button(action: {
                            HapticManager.impact(.medium)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                                pendingWorkoutType = nil
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                navigateToTodaysWorkout = true
                            }
                        }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Continue Program")
                                        .font(.system(size: 17, weight: .semibold))
                                    
                                    if let currentDay = generatedProgramService.currentDay {
                                        Text(currentDay.name)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: [accentColor, accentColor.opacity(0.85)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    // Subtle inner highlight
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                }
                            )
                            .shadow(color: accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        
                        // Skip and continue with custom/auto workout - Secondary action
                        Button(action: {
                            HapticManager.impact(.light)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if pendingWorkoutType == .custom {
                                    navigateToCustomWorkout = true
                                } else if pendingWorkoutType == .auto {
                                    // 🔧 Redirect to Workout tab's auto-gen flow
                                    workoutManager.shouldNavigateToAutoGen = true
                                }
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: pendingWorkoutType == .custom ? "plus.circle.fill" : "bolt.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                
                                Text("Start \(pendingWorkoutType == .custom ? "Custom" : "Auto") Workout Instead")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(accentColor)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                                    
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(accentColor.opacity(0.4), lineWidth: 1.5)
                                }
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        
                        // Cancel button - Tertiary action
                        Button(action: {
                            HapticManager.selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                                pendingWorkoutType = nil
                            }
                        }) {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: 360)
                .background(
                    ZStack {
                        // Main background
                        RoundedRectangle(cornerRadius: 24)
                            .fill(colorScheme == .dark 
                                ? Color(white: 0.12) 
                                : Color.white)
                        
                        // Subtle gradient overlay
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(colorScheme == .dark ? 0.08 : 0.03),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Border
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color.white.opacity(0.1), Color.clear]
                                        : [Color.white, Color.black.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15), radius: 30, x: 0, y: 15)
                .shadow(color: accentColor.opacity(0.15), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 24)
                .scaleEffect(showingProgramConflictAlert ? 1 : 0.9)
                .opacity(showingProgramConflictAlert ? 1 : 0)
            }
            .transition(.opacity)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingProgramConflictAlert)
        }
    }
    
    // Scale button style for interactive feedback
    struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }
    
    // MARK: - Custom Header View
    private var customHeaderView: some View {
        HStack {
            Image("fit33-logo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 140, height: 55)
                .clipped()
            
            Spacer()
            
            // Profile icon and timer grouped together
            HStack(spacing: 8) {
                // Profile button with hollow blue gradient ring and photo/person icon
                NavigationLink(destination: ProfileView()) {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            // Hollow ring with blue gradient
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: .blue.opacity(0.4), radius: 4, x: 0, y: 2)
                            
                            // Show profile photo if available (from cache or URL), otherwise person icon
                            if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                                Image(uiImage: cachedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            } else if let photoURL = profilePhotoURL, photoURL != "cached", let url = URL(string: photoURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 28, height: 28)
                                            .clipShape(Circle())
                                    case .failure(_), .empty:
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    @unknown default:
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Red indicator dot for pending requests or unread workouts
                        if friendPendingCount > 0 || friendUnreadWorkoutCount > 0 {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                                )
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .accessibilityLabel("Profile")
                .offset(y: 4) // Align with Fit33 logo
                
                // Active workout timer (only shows when workout is active)
                if workoutManager.isWorkoutActive {
                    Text(workoutManager.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                        )
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: workoutManager.isWorkoutActive)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Notification Permission Banner
    @State private var dismissedNotificationBanner = false
    
    private var notificationPermissionBanner: some View {
        Group {
            if !dismissedNotificationBanner {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        // Bell icon with animation
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange, Color.red.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stay on Track!")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Enable notifications to get workout reminders & celebrate your wins")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                        
                        // Dismiss button
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dismissedNotificationBanner = true
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(8)
                        }
                    }
                    
                    // Enable button
                    Button(action: {
                        HapticManager.impact(.medium)
                        // Check if we need to request permission or open settings
                        Task {
                            let settings = await UNUserNotificationCenter.current().notificationSettings()
                            if settings.authorizationStatus == .notDetermined {
                                // First time - request permission
                                let granted = await NotificationManager.shared.requestAuthorization()
                                if granted {
                                    await MainActor.run {
                                        withAnimation {
                                            dismissedNotificationBanner = true
                                        }
                                    }
                                }
                            } else {
                                // Already denied - open settings
                                await MainActor.run {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Enable Notifications")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.cardBackground)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top section with Welcome back and Level
            HStack {
                Text("Welcome back,")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // User Level Display - floating badge (no background)
                HStack(spacing: 4) {
                    Image(systemName: userManager.getLevelIcon())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(userManager.getLevelColor())
                    
                    Text(userManager.getLevelTitle())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(userManager.getLevelColor())
                }
            }
            
            // Bottom section with icon and user info
            HStack(spacing: 14) {
                // Hero icon - Flame with streak counter (tappable for info)
                Button(action: {
                    HapticManager.impact(.light)
                    showStreakInfo = true
                }) {
                    ZStack {
                        // Solid fill behind the flame to fill the hole
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange, Color.red.opacity(0.9)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 32, height: 32)
                            .offset(y: 6)
                        
                        // Flame icon
                        Image(systemName: "flame.fill")
                            .font(.system(size: 56, weight: .regular))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange, Color.red]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .orange.opacity(0.5), radius: 8, x: 0, y: 2)
                        
                        // Streak number centered in flame
                        Text("\(userManager.currentUser?.currentStreak ?? 0)")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                            .offset(y: 4) // Center in flame body
                    }
                    .frame(width: 58, height: 58)
                }
                .buttonStyle(.plain)
                
                // User info section - moved to the right
                VStack(alignment: .leading, spacing: 6) {
                    // Name only (streak is now in the flame icon)
                    Text(userManager.currentUser?.name ?? "Joe")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    // Motivational message - now prominent
                    Text(personalizedRecommendation?.message ?? currentMotivationalMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - blue glow like Favorites
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                
                // Blue/purple accent border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                Color.purple.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
    
    private var startWorkoutButton: some View {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                // Custom Workout Button
                Button(action: {
                    HapticManager.impact(.medium)
                    handleWorkoutSelection(type: .custom)
                }) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 50, height: 50)
                                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 4) {
                        Text("Custom Workout")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        
                        Text("Build your own")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: 160, height: 140)
                .background(
                    ZStack {
                        // Bottom shadow layer (deepest) - color glow
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08))
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
                                    colors: [Color.blue.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.cyan.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
                .shadow(color: .blue.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
                }
                .buttonStyle(PlainButtonStyle())
                
            // Auto Workout Button
            Button(action: {
                HapticManager.impact(.medium)
                handleWorkoutSelection(type: .auto)
            }) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.purple, Color.pink]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 50, height: 50)
                                .shadow(color: .purple.opacity(0.4), radius: 8, x: 0, y: 4)
                            
                            Image(systemName: "dumbbell.fill")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 4) {
                        Text("Auto Workout")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        
                        Text("Auto-generated routine")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: 160, height: 140)
                .background(
                    ZStack {
                        // Bottom shadow layer (deepest) - color glow
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.purple.opacity(colorScheme == .dark ? 0.15 : 0.08))
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
                                    colors: [Color.purple.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.pink.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
                .shadow(color: .purple.opacity(0.12), radius: 20, x: 0, y: 10)
                }
                .buttonStyle(PlainButtonStyle())
            
        }
    }
    
    private var destinationForTodaysWorkout: some View {
        Group {
            if let program = generatedProgramService.activeProgram,
               let currentDay = generatedProgramService.currentDay {
                SmartWorkoutPreviewView(
                    day: currentDay,
                    program: program
                )
                .environmentObject(workoutManager)
                .environmentObject(generatedProgramService)
            } else {
                EmptyView()
            }
        }
    }
    
    private func handleWorkoutSelection(type: PendingWorkoutType) {
        // 🔧 Debounce: Prevent double-taps
        guard !isNavigating else { return }
        isNavigating = true
        
        // Reset after a short delay to allow new navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isNavigating = false
        }
        
        if generatedProgramService.activeProgram != nil {
            // Show alert if there's an active program
            pendingWorkoutType = type
            showingProgramConflictAlert = true
        } else {
            // Proceed directly if no active program
            pendingWorkoutType = type
            if type == .custom {
                navigateToCustomWorkout = true
            } else if type == .auto {
                // 🔧 Redirect to Workout tab's auto-gen flow
                // This prevents cross-tab navigation issues when starting workout
                workoutManager.shouldNavigateToAutoGen = true
            }
        }
    }
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with stats
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("\(recentWorkouts.count + recentCardioWorkouts.count) workouts completed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                NavigationLink(destination: WorkoutHistoryFullView()) {
                    Text("View All")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            
            // Combined workout cards - mix strength and cardio workouts, sorted by date
            VStack(spacing: 12) {
                ForEach(combinedRecentWorkouts.prefix(4), id: \.id) { item in
                    switch item {
                    case .strength(let workout, let isMostRecent):
                        RecentWorkoutCard(workout: workout, isMostRecent: isMostRecent)
                    case .cardio(let cardioWorkout, let isMostRecent):
                        RecentCardioWorkoutCard(cardioWorkout: cardioWorkout, isMostRecent: isMostRecent)
                    }
                }
            }
        }
        .padding(24)
        .background(
            ZStack {
                // Clean gradient background matching WorkoutTabView exactly
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
        guard let mostRecentWorkout = recentWorkouts.first else {
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
    
    // Helper to convert color string to Color
    private func colorFromString(_ colorString: String) -> Color {
        switch colorString.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "teal": return .teal
        case "mint": return .mint
        default: return .blue
        }
    }
    
    private var statsOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Progress")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                StatCard(
                    title: "Workouts",
                    value: "\(userManager.currentUser?.totalWorkouts ?? 0)",
                    icon: "dumbbell.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Best Streak",
                    value: "\(userManager.currentUser?.longestStreak ?? 0)",
                    icon: "flame.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Level",
                    value: "\(userManager.getLevel())",
                    icon: "star.fill",
                    color: .yellow
                )
            }
        }
        .padding(24)
        .background(
            ZStack {
                // Outer container - darker to let inner cards pop (matches Recent Activity)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.11), Color(white: 0.07)]
                                : [Color(white: 0.96), Color(white: 0.94)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle top highlight
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.clear]
                                : [Color.white.opacity(0.8), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 16, x: 0, y: 8)
    }
    
    private func generateMotivationalMessage() -> String {
        let streak = userManager.currentUser?.currentStreak ?? 0
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        
        // Rich variety of messages based on context - emojis at end for alignment
        var messages: [String] = []
        
        // Streak-based messages
        if streak == 0 {
            messages = [
                "Today's the day to start something great! 💪",
                "Every champion started with day one. Let's go! 🚀",
                "Your fitness journey begins now! 🌟",
                "No streak? No problem. Start building today! 🔥"
            ]
        } else if streak == 1 {
            messages = [
                "Day 1 complete! The hardest part is done. 🔥",
                "You showed up! That's what matters most. 💪",
                "One day down, many more wins to come! 🚀",
                "First step taken! Momentum starts here. ⚡"
            ]
        } else if streak <= 3 {
            messages = [
                "\(streak) days in! You're building a habit. 🔥",
                "Showing up is the hardest part. You did it \(streak)x! 💪",
                "Consistency unlocked! Keep stacking days. 🚀",
                "\(streak)-day streak – your future self thanks you! ⭐"
            ]
        } else if streak <= 7 {
            messages = [
                "\(streak) days strong! You're in the top 20% now. 🔥",
                "Almost a full week! Champions are made here. 💪",
                "Discipline > motivation. You've got both! 🚀",
                "\(streak) days of proving you're unstoppable! ⚡"
            ]
        } else if streak <= 14 {
            messages = [
                "Over a week! This is when habits become identity. 🔥",
                "\(streak) days! You're outworking 90% of people. 💪",
                "\(streak)-day streak! You're built different. 🌟",
                "Double digits! Your dedication is inspiring. 🚀"
            ]
        } else if streak <= 30 {
            messages = [
                "\(streak) days! You've made fitness non-negotiable. 👑",
                "\(streak)-day legend! This is elite consistency. 🏆",
                "\(streak) days of pure dedication. Respect! 💎",
                "\(streak) days strong! Nothing can stop you now. ⚔️"
            ]
        } else {
            messages = [
                "\(streak) DAYS! You're in the top 1% of humanity. 👑",
                "\(streak)-day monster! You ARE a fitness machine. 🏆",
                "\(streak) days! You've mastered consistency. 💎",
                "\(streak) days! You're rewriting your story. 🔥",
                "\(streak) days! Your discipline is legendary. ⭐"
            ]
        }
        
        // Add time-of-day specific messages
        if hour < 9 {
            messages.append(contentsOf: [
                "Early bird energy! Morning warriors win the day. ☀️",
                "Rise and grind! Best time to invest in yourself. 🌅",
                "Morning check-in! You're already ahead. ⚡"
            ])
        } else if hour >= 17 && hour < 21 {
            messages.append(contentsOf: [
                "Evening power! Perfect time for gains. 🌙",
                "End the day strong! Your body is ready. 💪",
                "Evening workout = better sleep tonight. 🔥"
            ])
        }
        
        // Day-specific messages
        if dayOfWeek == 2 { // Monday
            messages.append(contentsOf: [
                "Monday momentum! Set the tone for the week. 💪",
                "New week, new opportunities to level up! 🚀",
                "Monday warriors build championship weeks. 🔥"
            ])
        } else if dayOfWeek == 6 { // Friday
            messages.append(contentsOf: [
                "Friday finish! End the week on a high note. 🎉",
                "Weekend warrior mode: activated! 💪",
                "Friday flex! You earned this week. 🏆"
            ])
        } else if dayOfWeek == 1 || dayOfWeek == 7 { // Weekend
            messages.append(contentsOf: [
                "Weekend dedication = next-level results. 🌴",
                "Weekends count too! Stay locked in. 💪",
                "Weekend warriors separate themselves here. ⚡"
            ])
        }
        
        return messages.randomElement() ?? "Let's make today count! 💪"
    }
    
    // MARK: - Smart Active Program Widget
    
    private func smartActiveProgramWidget(program: DynamicProgramGenerator.GeneratedProgram) -> some View {
        let displayInfo = generatedProgramService.getDisplayInfo(for: program)
        let programColor = colorFromProgramType(program.programType)
        let completedDays = program.generatedDays.filter { $0.isCompleted }.count
        let totalDays = program.durationWeeks * program.daysPerWeek
        
        return VStack(spacing: 0) {
            // Streamlined Header
            VStack(spacing: 10) {
                // Top row: Icon, Name, and Menu
                HStack(alignment: .center, spacing: 12) {
                    // Gradient icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [programColor, programColor.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: programColor.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: program.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(program.name)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        HStack(spacing: 8) {
                            // Week and progress combined
                            Text("Week \(displayInfo.currentWeek)/\(program.durationWeeks)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    // View all button - placeholder for GeneratedProgram (would need adapter)
                    NavigationLink(destination: Text("Program Details - Coming Soon")) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Compact progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 8)
                        
                        // Progress fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * (displayInfo.progressPercentage / 100), height: 8)
                        
                        // Percentage overlay
                        HStack {
                            Spacer()
                            Text("\(Int(displayInfo.progressPercentage))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor((displayInfo.progressPercentage / 100) > 0.15 ? .white : programColor)
                                .padding(.trailing, 6)
                        }
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            
            // Today's workout - COMPACT with rounded inner card
            if let currentDay = generatedProgramService.currentDay {
                NavigationLink(destination: SmartWorkoutPreviewView(
                    day: currentDay,
                    program: program
                ).environmentObject(generatedProgramService)) {
                    HStack(spacing: 12) {
                        // Left: Workout info
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(currentDay.name)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Text("Day \(currentDay.dayNumber)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(programColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(programColor.opacity(0.12))
                                    )
                            }
                            
                            HStack(spacing: 6) {
                                Label("\(currentDay.exercises.count)", systemImage: "dumbbell.fill")
                                Label("~\(currentDay.estimatedDuration)min", systemImage: "clock")
                                
                                // Muscle targets from focusMuscles
                                if !currentDay.focusMuscles.isEmpty {
                                    Text("•")
                                        .font(.caption2)
                                    Text(currentDay.focusMuscles.prefix(3).joined(separator: ", "))
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Right: Start button
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Start")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            ZStack {
                // Base gradient
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color(white: 0.12)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner glow
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Accent border
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.3), programColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
        // Subtle glow effect to draw attention
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 16, x: 0, y: 0)
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 24, x: 0, y: 0)
    }
    
    // MARK: - Unified Smart Program Widget
    
    /// Determines if this is a brand new user who hasn't started any workout or program
    private var isFirstTimeUser: Bool {
        let totalWorkouts = userManager.currentUser?.totalWorkouts ?? 0
        let hasStartedProgram = !smartProgramEngine.userPrograms.isEmpty
        return totalWorkouts == 0 && !hasStartedProgram
    }
    
    /// Get the 10 personalized programs from SmartProgramEngine
    private var personalizedPrograms: [PersonalizedProgram] {
        smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
    }
    
    /// Get the best recommended program (highest match, unlocked)
    private var topRecommendedSmartProgram: PersonalizedProgram? {
        personalizedPrograms
            .filter { !$0.isCompleted && $0.isUnlocked }
            .sorted { $0.matchPercentage > $1.matchPercentage }
            .first
    }
    
    /// Get active SmartProgram if any (most recently started)
    private var activeSmartProgramForWidget: SmartActiveProgram? {
        smartProgramEngine.userPrograms
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }  // Most recent first
            .first
    }
    
    /// Compute widget refresh ID based on program state
    private var activeProgramWidgetId: String {
        guard let program = activeSmartProgramForWidget else { return "none" }
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        return "\(program.id)-\(program.completedDays.count)-\(currentDay?.isCompleted ?? false)"
    }
    
    @ViewBuilder
    private var unifiedProgramWidget: some View {
        if !userManager.hasCompletedOnboarding {
            EmptyView()
        } else if let activeProgram = activeSmartProgramForWidget {
            activeSmartProgramDetailWidget(program: activeProgram)
                .id(activeProgramWidgetId)
        } else if isFirstTimeUser {
            getStartedSmartWidget
        } else if let recommended = topRecommendedSmartProgram {
            recommendedSmartProgramWidget(program: recommended)
        } else {
            browseProgramsWidget
        }
    }
    
    // MARK: - Get Started Widget (First Time Users) - Uses SmartProgramEngine
    
    private var getStartedSmartWidget: some View {
        let accentColor = Color.green
        
        return VStack(spacing: 10) {
            // Compact header with icon and text side by side
            HStack(spacing: 12) {
                // Sparkle icon - smaller
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.2), accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Started!")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("10 programs created for you")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Show top recommended program preview
            if let program = topRecommendedSmartProgram {
                let template = program.template
                let totalWeeks = (template.totalDays + 6) / 7
                
                HStack(spacing: 10) {
                    // Program icon - smaller
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: template.category.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(program.personalizedName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            Text("\(totalWeeks) weeks")
                            Text("•")
                            Text("\(program.matchPercentage)% match")
                                .foregroundColor(accentColor)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("Start")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, accentColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
                )
                .onTapGesture {
                    if let user = userManager.currentUser {
                        _ = SmartProgramEngine.shared.startProgram(templateId: template.id, for: user)
                    }
                }
            }
            
            // Divider
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.horizontal, 16)
            
            // Or explore all programs
            Button(action: {
                // 🔧 Redirect to Workout tab's programs view
                workoutManager.shouldNavigateToPrograms = true
            }) {
                Text("or explore all programs →")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.3), accentColor.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: accentColor.opacity(0.15), radius: 20, x: 0, y: 8)
    }
    
    // MARK: - Recommended For You Widget (Returning Users) - Uses SmartProgramEngine
    
    private func recommendedSmartProgramWidget(program: PersonalizedProgram) -> some View {
        let template = program.template
        let programColor = Color.green
        let totalWeeks = (template.totalDays + 6) / 7
        
        return VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommended for You")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(programColor)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(program.personalizedName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Match percentage badge
                VStack(spacing: 2) {
                    Text("\(program.matchPercentage)%")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(programColor)
                    Text("match")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.trailing, 8)
                
                // Program icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: programColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: template.category.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 12)
            
            // Program details
            HStack(spacing: 16) {
                programDetailPill(icon: "calendar", value: "\(totalWeeks)", label: "weeks")
                programDetailPill(icon: "flame.fill", value: "\(template.daysPerWeek)", label: "days/wk")
                programDetailPill(icon: "clock.fill", value: "\(template.estimatedMinutesPerDay)", label: "min")
            }
            .padding(.bottom, 16)
            
            // Description
            Text(program.personalizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            
            // Start button
            Button(action: {
                if let user = userManager.currentUser {
                    _ = SmartProgramEngine.shared.startProgram(templateId: template.id, for: user)
                }
            }) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Start Program")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [programColor, programColor.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: programColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            // View all programs link
            NavigationLink(destination: PersonalizedProgramsView().environmentObject(userManager)) {
                Text("View All 10 Programs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 12)
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Accent glow
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.4), programColor.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 8)
    }
    
    private func programDetailPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
        )
    }
    
    // MARK: - Active Smart Program Widget (With Today/Tomorrow Preview)
    
    @State private var activeWidgetGlowRotation: Double = 0
    
    private func activeSmartProgramDetailWidget(program: SmartActiveProgram) -> some View {
        let programColor = Color.green
        let template = personalizedPrograms.first { $0.template.id == program.templateId }?.template
        let completedDays = program.completedDays.count
        let totalDays = template?.totalDays ?? program.generatedDays.count
        let totalWeeks = (totalDays + 6) / 7
        let currentWeek = (program.currentDay - 1) / max(1, template?.daysPerWeek ?? 4) + 1
        let progress = totalDays > 0 ? Double(completedDays) / Double(totalDays) * 100 : 0
        
        // Determine which day to show
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        let isTodayCompleted = currentDay?.isCompleted ?? false
        let nextDay = program.generatedDays.first { !$0.isCompleted && $0.dayNumber > program.currentDay }
        let dayToShow = isTodayCompleted ? nextDay : currentDay
        let dayLabel = isTodayCompleted ? "Tomorrow's Workout" : "Today's Workout"
        
        return VStack(spacing: 0) {
            // Header - Tap anywhere to go to Program Overview (on Workout tab)
            Button {
                workoutManager.navigateProgramData = program
                workoutManager.navigateProgramTemplate = template
                workoutManager.shouldNavigateToProgramOverview = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    // Progress ring as icon
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .trim(from: 0, to: progress / 100)
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
                        
                        Text("\(Int(progress))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(programColor)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template?.baseName ?? "Training Program")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text("Week \(currentWeek)/\(totalWeeks)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Today/Tomorrow's workout section
            if isTodayCompleted {
                // Completed state - "Great work!" message
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Great work!")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if let next = nextDay {
                            Text("Next up: \(next.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("You're all caught up!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if let next = nextDay {
                        Button {
                            workoutManager.navigateProgramData = program
                            workoutManager.navigateProgramDay = next
                            workoutManager.shouldNavigateToProgramDay = true
                        } label: {
                            Text("Preview")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(programColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .stroke(programColor.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(colorScheme == .dark ? 0.08 : 0.06))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else if let day = dayToShow {
                // Active workout - Left accent bar style (navigates to Workout tab)
                Button {
                    workoutManager.navigateProgramData = program
                    workoutManager.navigateProgramDay = day
                    workoutManager.shouldNavigateToProgramDay = true
                } label: {
                    HStack(spacing: 0) {
                        // Left accent bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(programColor)
                            .frame(width: 4)
                            .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            // Workout info
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(day.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Day \(day.dayNumber)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(programColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(programColor.opacity(0.15))
                                        )
                                }
                                
                                HStack(spacing: 4) {
                                    Text("\(day.exercises.count) exercises")
                                    let muscleTargets = getMuscleTargets(for: day.exercises)
                                    if !muscleTargets.isEmpty {
                                        Text("•")
                                            .font(.caption2)
                                        Text(muscleTargets)
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Start button
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Start")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 14)
                    }
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark 
                                ? Color.white.opacity(0.04) 
                                : Color.black.opacity(0.03))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                // All days completed
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.yellow)
                    
                    Text("Program Complete! 🎉")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Congratulations on finishing your program!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
        }
        .background(
            ZStack {
                // Rotating glow when workout not complete
                if !isTodayCompleted {
                    // Outer glow layer
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    programColor.opacity(0.7),
                                    programColor.opacity(0.3),
                                    programColor.opacity(0.05),
                                    Color.clear,
                                    programColor.opacity(0.05),
                                    programColor.opacity(0.3),
                                    programColor.opacity(0.7)
                                ],
                                center: .center,
                                startAngle: .degrees(activeWidgetGlowRotation),
                                endAngle: .degrees(activeWidgetGlowRotation + 360)
                            ),
                            lineWidth: 4
                        )
                        .blur(radius: 6)
                    
                    // Inner sharper glow
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    programColor.opacity(0.8),
                                    programColor.opacity(0.2),
                                    Color.clear,
                                    Color.clear,
                                    programColor.opacity(0.2),
                                    programColor.opacity(0.8)
                                ],
                                center: .center,
                                startAngle: .degrees(activeWidgetGlowRotation),
                                endAngle: .degrees(activeWidgetGlowRotation + 360)
                            ),
                            lineWidth: 2
                        )
                        .blur(radius: 2)
                }
                
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Accent border - muted when completed
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: isTodayCompleted 
                                ? [Color.gray.opacity(0.15), Color.gray.opacity(0.05), Color.clear]
                                : [programColor.opacity(0.3), programColor.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: !isTodayCompleted ? programColor.opacity(colorScheme == .dark ? 0.35 : 0.25) : Color.black.opacity(colorScheme == .dark ? 0.15 : 0.06), radius: !isTodayCompleted ? 24 : 12, x: 0, y: !isTodayCompleted ? 8 : 4)
    }
    
    // MARK: - Browse Programs Widget (Fallback)
    
    private var browseProgramsWidget: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)
            
            Text("Explore Programs")
                .font(.headline)
                .fontWeight(.bold)
            
            Text("Find a program that fits your goals")
                .font(.caption)
                .foregroundColor(.secondary)
            
            NavigationLink(destination: GeneratedProgramsListView()) {
                Text("Browse Programs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Program Recommendations Widget (Legacy - kept for scrolling list)
    
    private var smartProgramRecommendationsWidget: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your Programs")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                NavigationLink(destination: GeneratedProgramsListView()) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            
            // Show top 2 program recommendations
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(generatedProgramService.generatedPrograms.prefix(3)) { program in
                        SmartProgramMiniCard(
                            program: program,
                            onStart: {
                                generatedProgramService.startProgram(program)
                            }
                        )
                        .frame(width: 260)
                    }
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color(white: 0.12)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: 20)
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Smart Programs Widget (context-aware)
    
    private var activeSmartProgram: SmartActiveProgram? {
        smartProgramEngine.userPrograms
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }  // Most recent first
            .first
    }
    
    private var generateProgramsWidget: some View {
        Group {
            if let activeProgram = activeSmartProgram {
                // Show active program status
                activeProgramWidget(activeProgram)
            } else {
                // Show browse programs card
                browseProgramsCard
            }
        }
    }
    
    // MARK: - Active Program Widget
    
    @State private var navigateToProgramDay = false
    
    private func activeProgramWidget(_ program: SmartActiveProgram) -> some View {
        let template = smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
            .first { $0.template.id == program.templateId }?.template
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        let isTodayCompleted = currentDay?.isCompleted ?? false
        let nextDay = program.generatedDays.first { $0.dayNumber == program.currentDay + 1 }
        let completedDays = program.completedDays.count
        let totalDays = template?.totalDays ?? 1
        let progressPercent = Double(completedDays) / Double(totalDays)
        let programColor: Color = .green
        let currentWeek = (program.currentDay - 1) / 7 + 1
        let totalWeeks = (totalDays + 6) / 7
        
        return VStack(spacing: 0) {
            // Streamlined Header
            VStack(spacing: 10) {
                // Top row: Icon, Name, and Menu
                HStack(alignment: .center, spacing: 12) {
                    // Gradient icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [programColor, programColor.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: programColor.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(program.personalizedName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            // Week and progress combined
                            Text("Week \(currentWeek)/\(totalWeeks)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    // View all button
                    NavigationLink(destination: SmartProgramOverviewView(
                        program: program,
                        template: template
                    )
                    .environmentObject(workoutManager)
                    .environmentObject(userManager)) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Compact progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 8)
                        
                        // Progress fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progressPercent, height: 8)
                        
                        // Percentage overlay
                        HStack {
                            Spacer()
                            Text("\(Int(progressPercent * 100))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(progressPercent > 0.15 ? .white : programColor)
                                .padding(.trailing, 6)
                        }
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            
            // Today's workout - COMPACT
            if let day = currentDay {
                if !isTodayCompleted && !day.exercises.isEmpty {
                    NavigationLink(destination: SmartProgramDayPreviewView(
                        program: program,
                        day: day,
                        programName: program.personalizedName,
                        totalDays: totalDays
                    )
                    .environmentObject(workoutManager)
                    .environmentObject(userManager)) {
                        HStack(spacing: 12) {
                            // Left: Workout info
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(day.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Day \(day.dayNumber)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(programColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(programColor.opacity(0.12))
                                        )
                                }
                                
                                HStack(spacing: 6) {
                                    Label("\(day.exercises.count)", systemImage: "dumbbell.fill")
                                    Label("~\(day.targetDuration)min", systemImage: "clock")
                                    
                                    // Muscle targets
                                    let muscleTargets = getMuscleTargets(for: day.exercises)
                                    if !muscleTargets.isEmpty {
                                        Text("•")
                                            .font(.caption2)
                                        Text(muscleTargets)
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Right: Start button
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Start")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else if isTodayCompleted {
                    // Today completed view - more compact
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Great work!")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            if let next = nextDay {
                                Text("Tomorrow: \(next.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green.opacity(0.12))
                    )
                    .padding(.horizontal, 14)
                } else if day.exercises.isEmpty {
                    // Rest day - more compact
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rest Day")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Recovery is important!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.blue.opacity(0.12))
                    )
                    .padding(.horizontal, 14)
                }
            }
        }
        .background(
            ZStack {
                // Base gradient
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color(white: 0.12)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner glow
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Accent border
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.3), programColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
        // Subtle glow effect to draw attention
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 16, x: 0, y: 0)
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 24, x: 0, y: 0)
    }
    
    // MARK: - Helper: Extract Muscle Targets from Exercises
    
    private func getMuscleTargets(for exercises: [SmartProgramExercise]) -> String {
        let exerciseLibrary = ExerciseLibraryService.shared
        var muscleGroups: [String: Int] = [:]
        
        for exercise in exercises {
            // Try to find the exercise in the library
            if let libraryExercise = exerciseLibrary.getExercise(byName: exercise.exerciseName) {
                if let muscles = libraryExercise.muscleGroups as? [String], let primary = muscles.first {
                    muscleGroups[primary, default: 0] += 1
                }
            } else {
                // Fallback: extract from exercise name
                let nameLower = exercise.exerciseName.lowercased()
                if nameLower.contains("chest") || nameLower.contains("bench") || nameLower.contains("fly") {
                    muscleGroups["Chest", default: 0] += 1
                } else if nameLower.contains("back") || nameLower.contains("row") || nameLower.contains("lat") || nameLower.contains("pull") {
                    muscleGroups["Back", default: 0] += 1
                } else if nameLower.contains("shoulder") || nameLower.contains("delt") || nameLower.contains("press") {
                    muscleGroups["Shoulders", default: 0] += 1
                } else if nameLower.contains("bicep") || nameLower.contains("curl") || nameLower.contains("tricep") {
                    muscleGroups["Arms", default: 0] += 1
                } else if nameLower.contains("leg") || nameLower.contains("squat") || nameLower.contains("quad") || nameLower.contains("hamstring") || nameLower.contains("glute") {
                    muscleGroups["Legs", default: 0] += 1
                } else if nameLower.contains("core") || nameLower.contains("ab") || nameLower.contains("plank") {
                    muscleGroups["Core", default: 0] += 1
                }
            }
        }
        
        // Sort by count and take top 2-3
        let sorted = muscleGroups.sorted { $0.value > $1.value }
        let topMuscles = sorted.prefix(3).map { $0.key }
        
        return topMuscles.joined(separator: ", ")
    }
    
    // MARK: - Your Perfect Program Widget (no active program)
    
    private var topRecommendedProgram: PersonalizedProgram? {
        smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
            .filter { !$0.isCompleted && $0.isUnlocked }
            .first
    }
    
    private var browseProgramsCard: some View {
        Group {
            if let recommended = topRecommendedProgram {
                perfectProgramWidget(program: recommended)
            } else {
                fallbackProgramsCard
            }
        }
    }
    
    @State private var showStartProgramConfirm = false
    @State private var programToStart: PersonalizedProgram?
    @State private var programGlowRotation: Double = 0
    
    private func perfectProgramWidget(program: PersonalizedProgram) -> some View {
        let template = program.template
        let matchPercent = program.matchPercentage
        let accentColor = Color.green
        let totalWeeks = (template.totalDays + 6) / 7
        
        return NavigationLink(destination: PersonalizedProgramsView().environmentObject(userManager)) {
            HStack(spacing: 14) {
                // Program icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, Color.mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                
                // Program info
                VStack(alignment: .leading, spacing: 5) {
                    Text(program.personalizedName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        Text("\(totalWeeks)wk • \(template.daysPerWeek)x/wk")
                        Text("•")
                        Text("\(matchPercent)% match")
                            .foregroundColor(accentColor)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Compact start button
                Button {
                    HapticManager.impact(.medium)
                    programToStart = program
                    showStartProgramConfirm = true
                } label: {
                    Text("Start")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, Color.mint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(
                ZStack {
                    // Animated glow border - more evenly distributed
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4)
                                ]),
                                center: .center,
                                startAngle: .degrees(programGlowRotation),
                                endAngle: .degrees(programGlowRotation + 360)
                            ),
                            lineWidth: 3
                        )
                        .blur(radius: 6)

                    // Main background
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBackgroundGradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Inner border - more evenly distributed
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3)
                                ]),
                                center: .center,
                                startAngle: .degrees(programGlowRotation),
                                endAngle: .degrees(programGlowRotation + 360)
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.25 : 0.15), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Start \(program.personalizedName)?", isPresented: $showStartProgramConfirm, titleVisibility: .visible) {
            Button("Start Program") {
                if let toStart = programToStart,
                   let user = userManager.currentUser {
                    _ = SmartProgramEngine.shared.startProgram(templateId: toStart.template.id, for: user)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This \(totalWeeks)-week program is \(matchPercent)% matched to your goals and equipment.")
        }
    }
    
    // Fallback card if no programs available
    private var fallbackProgramsCard: some View {
        NavigationLink(destination: PersonalizedProgramsView().environmentObject(userManager)) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green, Color.mint]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 4) {
                    Text("Training Programs")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("10 personalized plans")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: cardBackgroundGradient,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
            )
            .shadow(color: .green.opacity(0.2), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Functions
    
    private func colorFromProgramType(_ type: DynamicProgramGenerator.GeneratedProgram.ProgramType) -> Color {
        switch type {
        case .hypertrophy: return .blue
        case .strength: return .red
        case .fatLoss: return .orange
        case .toning: return .purple
        case .generalFitness: return .green
        case .powerbuilding: return .yellow
        }
    }
}

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
                Text("Start")
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

struct RecentWorkoutCard: View {
    let workout: Workout
    var isMostRecent: Bool = false // Whether this is the most recent workout (gets special outline)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    // Get exercises from workout
    private var workoutExercises: [WorkoutExercise] {
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        return exercises.sorted { ($0.order) < ($1.order) }
    }
    
    // Smart workout name based on muscle groups
    private var smartWorkoutName: String {
        // First check if it's a program day name (not generic)
        if let name = workout.name, !name.isEmpty {
            let cleanName = cleanWorkoutName(name)
            // If it's a meaningful program name (not just "Workout" or generic)
            if !cleanName.lowercased().contains("workout") || cleanName.count > 15 {
                return cleanName
            }
        }
        
        // Otherwise, generate smart name from muscle groups
        return generateMuscleBasedName()
    }
    
    private func generateMuscleBasedName() -> String {
        var muscleCount: [String: Int] = [:]
        
        for workoutExercise in workoutExercises {
            // Use safeMuscleGroups to handle nil exercise relationships
            for muscle in workoutExercise.safeMuscleGroups {
                muscleCount[muscle.lowercased(), default: 0] += 1
            }
        }
        
        // Sort by count
        let sortedMuscles = muscleCount.sorted { $0.value > $1.value }
        let timeOfDay = getTimeOfDay(for: workout.date ?? Date())
        
        if sortedMuscles.isEmpty {
            return "\(timeOfDay) Workout"
        }
        
        // Check if one muscle dominates (>50% of exercises)
        let total = sortedMuscles.reduce(0) { $0 + $1.value }
        if let topMuscle = sortedMuscles.first, total > 0, Double(topMuscle.value) / Double(total) > 0.5 {
            return "\(timeOfDay) \(topMuscle.key.capitalized)"
        }
        
        // Otherwise, combine top 2 muscles
        if sortedMuscles.count >= 2 {
            return "\(sortedMuscles[0].key.capitalized) & \(sortedMuscles[1].key.capitalized)"
        }
        
        return "\(timeOfDay) \(sortedMuscles[0].key.capitalized)"
    }
    
    private func getTimeOfDay(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 5 && hour < 12 {
            return "Morning"
        } else if hour >= 12 && hour < 17 {
            return "Afternoon"
        } else {
            return "Evening"
        }
    }
    
    private var workoutGradient: [Color] {
        // Color based on primary muscle group (use safeMuscleGroups for nil-safety)
        let muscles = workoutExercises.compactMap { $0.safeMuscleGroups.first?.lowercased() }
        let primaryMuscle = muscles.first ?? ""
        
        switch primaryMuscle {
        case "chest": return [.red, .orange]
        case "back": return [.blue, .cyan]
        case "legs", "quads", "hamstrings", "glutes": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "biceps", "triceps", "arms": return [.purple, .pink]
        case "core", "abs": return [.yellow, .orange]
        default:
            // Fallback to time-based
            let hour = Calendar.current.component(.hour, from: workout.date ?? Date())
            if hour >= 5 && hour < 12 {
                return [.orange, .yellow]
            } else if hour >= 12 && hour < 17 {
                return [.blue, .cyan]
            } else {
                return [.purple, .pink]
            }
        }
    }
    
    // Exercise count
    private var exerciseCount: Int {
        workoutExercises.count
    }
    
    // Total sets completed
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
    }
    
    // Total volume
    private var totalVolume: Double {
        workoutExercises.reduce(0.0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }
    
    // Top muscles worked (for preview)
    private var topMuscles: [String] {
        var muscleCount: [String: Int] = [:]
        for workoutExercise in workoutExercises {
            // Use safeMuscleGroups for nil-safety
            for muscle in workoutExercise.safeMuscleGroups {
                muscleCount[muscle.capitalized, default: 0] += 1
            }
        }
        return muscleCount.sorted { $0.value > $1.value }.prefix(2).map { $0.key }
    }
    
    // Toggle favorite status
    private func toggleFavorite() {
        workout.isFavorite.toggle()
        
        do {
            try viewContext.save()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            // Log the action
            SessionLogManager.shared.log(.info, category: .userAction, message: workout.isFavorite ? "⭐ Workout favorited" : "☆ Workout unfavorited", metadata: [
                "workout_id": workout.objectID.uriRepresentation().absoluteString,
                "workout_name": smartWorkoutName
            ])
        } catch {
            print("❌ Error saving favorite status: \(error)")
        }
    }
    
    var body: some View {
        NavigationLink(destination: WorkoutHistoryDetailView(workout: workout)) {
            VStack(alignment: .leading, spacing: 0) {
                // Top section - Title and Date
                HStack(alignment: .top, spacing: 12) {
                    // Hollow transparent icon with gradient ring and checkmark
                    ZStack {
                        // Hollow circle with gradient stroke - fully transparent inside
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: workoutGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 52, height: 52)
                        
                        // Gradient checkmark floating inside
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: workoutGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Smart workout name
                        Text(smartWorkoutName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        // Date with relative time
                        Text(formatSmartDate(workout.date ?? Date()))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Favorite star button
                    Button(action: {
                        toggleFavorite()
                    }) {
                        Image(systemName: workout.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(workout.isFavorite ? .yellow : .gray.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 8)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                Divider()
                    .padding(.vertical, 12)
                
                // Bottom section - Stats
                HStack(spacing: 0) {
                    // Duration
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                                .foregroundColor(workoutGradient[0])
                            Text(formatDuration(workout.duration))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("Duration")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 35)
                    
                    // Exercises
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 12))
                                .foregroundColor(workoutGradient[0])
                            Text("\(exerciseCount)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("Exercises")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 35)
                    
                    // Sets
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .font(.system(size: 12))
                                .foregroundColor(workoutGradient[0])
                            Text("\(totalSets)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("Sets")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 35)
                    
                    // XP
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("+\(Int(workout.xpEarned))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("XP")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Muscle tags (if available)
                if !topMuscles.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(topMuscles, id: \.self) { muscle in
                            Text(muscle)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(workoutGradient[0])
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(workoutGradient[0].opacity(0.12))
                                )
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today · \(formatTime(date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday · \(formatTime(date))"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name
            return "\(formatter.string(from: date)) · \(formatTime(date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: date)) · \(formatTime(date))"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private func getDayName(for date: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // Full day name
        return dayFormatter.string(from: date)
    }
    
    private func getWorkoutType(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        // Determine time of day
        let timeOfDay: String
        if hour >= 5 && hour < 12 {
            timeOfDay = "Morning"
        } else if hour >= 12 && hour < 17 {
            timeOfDay = "Afternoon"
        } else {
            timeOfDay = "Evening"
        }
        
        return "\(timeOfDay) workout"
    }
    
    private func generateSmartWorkoutTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        // Get day name
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // Full day name
        let dayName = dayFormatter.string(from: date)
        
        // Determine time of day
        let timeOfDay: String
        if hour >= 5 && hour < 12 {
            timeOfDay = "Morning"
        } else if hour >= 12 && hour < 17 {
            timeOfDay = "Afternoon"
        } else {
            timeOfDay = "Evening"
        }
        
        // Create smart title
        return "\(dayName) \(timeOfDay) Workout"
    }
    
    private func formatCompactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func cleanWorkoutName(_ name: String) -> String {
        // Remove any date suffixes like " - Nov 22" or " - Nov"
        var cleanName = name
        
        // Pattern to match " - Month" or " - Month Day" at the end
        let patterns = [
            " - [A-Z][a-z]+ \\d+$",  // Matches " - Nov 22"
            " - [A-Z][a-z]+$",       // Matches " - Nov"
            " - \\d{1,2}/\\d{1,2}$", // Matches " - 11/22"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleanName.startIndex..., in: cleanName)
                cleanName = regex.stringByReplacingMatches(in: cleanName, range: range, withTemplate: "")
            }
        }
        
        return cleanName.trimmingCharacters(in: .whitespaces)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        // Add ordinal suffix
        let day = Calendar.current.component(.day, from: date)
        let ordinalFormatter = NumberFormatter()
        ordinalFormatter.numberStyle = .ordinal
        let ordinalDay = ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)
        let year = Calendar.current.component(.year, from: date)
        
        return "\(month) \(ordinalDay), \(year)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatDuration(_ duration: Int32) -> String {
        let minutes = duration / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// MARK: - Recent Cardio Workout Card
struct RecentCardioWorkoutCard: View {
    let cardioWorkout: CardioWorkoutDTO
    var isMostRecent: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Parse completed date (uses centralized cached formatters)
    private var completedDate: Date {
        return ISO8601Parser.parse(cardioWorkout.completedAt, fallback: Date())
    }
    
    // Activity type display name and icon
    private var activityInfo: (name: String, icon: String, color: Color) {
        let type = cardioWorkout.activityType.lowercased().replacingOccurrences(of: "_", with: " ")
        switch type {
        case "outdoor run", "run":
            return ("Outdoor Run", "figure.run", .green)
        case "treadmill":
            return ("Treadmill", "figure.walk.motion", .orange)
        case "walk":
            return ("Walk", "figure.walk", .blue)
        case "indoor cycle", "indoor_cycle":
            return ("Indoor Cycle", "bicycle", .cyan)
        case "outdoor cycle", "outdoor_cycle":
            return ("Outdoor Cycle", "bicycle", .green)
        case "rowing":
            return ("Rowing", "figure.rower", .blue)
        case "elliptical":
            return ("Elliptical", "figure.elliptical", .purple)
        case "stair climber", "stair_climber":
            return ("Stair Climber", "figure.stairs", .orange)
        case "hiit":
            return ("HIIT", "flame.fill", .red)
        case "swimming":
            return ("Swimming", "figure.pool.swim", .cyan)
        default:
            return (type.capitalized, "figure.run", .green)
        }
    }
    
    // Format duration
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
    
    // Format distance
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        if km < 1 {
            return String(format: "%.0fm", meters)
        } else {
            return String(format: "%.2fkm", km)
        }
    }
    
    // Format pace
    private func formatPace(_ pace: Double?) -> String {
        guard let pace = pace, pace > 0 else { return "--" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        NavigationLink(destination: CardioWorkoutDetailView(cardioWorkout: cardioWorkout)) {
            VStack(alignment: .leading, spacing: 0) {
                // Top section - Title and Date
                HStack(alignment: .top, spacing: 12) {
                    // Activity icon with gradient ring
                    ZStack {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [activityInfo.color, activityInfo.color.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 52, height: 52)
                        
                        Image(systemName: activityInfo.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [activityInfo.color, activityInfo.color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Activity name with Cardio badge
                        HStack(spacing: 8) {
                            Text(activityInfo.name)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            // Cardio badge in activity color
                            Text("Cardio")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(activityInfo.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(activityInfo.color.opacity(0.15))
                                )
                        }
                        
                        // Date with relative time
                        Text(DateFormatUtils.formatSmartDate(completedDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Goal achieved badge
                    if cardioWorkout.goalAchieved {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                            .padding(.trailing, 8)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                    }
                
                    Divider()
                        .padding(.vertical, 12)
                
                    // Bottom section - Cardio Stats
                    HStack(spacing: 0) {
                        // Duration
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(activityInfo.color)
                                Text(formatDuration(cardioWorkout.durationSeconds))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("Duration")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1, height: 35)
                        
                        // Distance
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(activityInfo.color)
                                Text(formatDistance(cardioWorkout.distanceMeters))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("Distance")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1, height: 35)
                        
                        // Calories
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                Text("\(Int(cardioWorkout.caloriesBurned))")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("Calories")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1, height: 35)
                        
                        // Pace
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "speedometer")
                                    .font(.system(size: 12))
                                    .foregroundColor(.purple)
                                Text(formatPace(cardioWorkout.averagePace))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("/km")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                
                    // Heart rate tag (if available)
                    if let heartRate = cardioWorkout.averageHeartRate, heartRate > 0 {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                Text("\(heartRate) bpm")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.12))
                            )
                            
                            Spacer()
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                )
            }
            .buttonStyle(PlainButtonStyle())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                // Card fill - lighter to pop from container
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.18), Color(white: 0.14)]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle top highlight
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.clear]
                                : [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
    }
}

enum WorkoutCreationType {
    case custom
    case generated
}

enum PendingWorkoutType {
    case custom
    case auto
}

// MARK: - Program Stat Pill Component
struct ProgramStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct DashboardScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Workout History Full View (Full Page Navigation)
struct WorkoutHistoryFullView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == true"),
        animation: .none)  // Disable animation for faster scroll
    private var allWorkouts: FetchedResults<Workout>
    
    // Group workouts by date
    private var groupedWorkouts: [(Date, [Workout])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allWorkouts) { workout in
            calendar.startOfDay(for: workout.date ?? Date())
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    // Stats
    private var totalWorkouts: Int { allWorkouts.count }
    private var totalExercises: Int {
        allWorkouts.reduce(0) { $0 + (($1.exercises?.count) ?? 0) }
    }
    private var totalDuration: TimeInterval {
        allWorkouts.reduce(0.0) { $0 + Double($1.duration) }
    }
    
    var body: some View {
        ZStack {
            // Background
            AdaptiveGradient.home(for: colorScheme)
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Stats summary
                    statsHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    
                    // Workout list
                    if groupedWorkouts.isEmpty {
                        emptyStateView
                            .padding(.horizontal, 20)
                    } else {
                        LazyVStack(spacing: 20) {
                            ForEach(Array(groupedWorkouts.enumerated()), id: \.offset) { _, dayGroup in
                                WorkoutHistoryDaySection(date: dayGroup.0, workouts: dayGroup.1)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 12) {
            HistoryStatPill(icon: "flame.fill", value: "\(totalWorkouts)", label: "Workouts", color: .orange)
            HistoryStatPill(icon: "figure.strengthtraining.traditional", value: "\(totalExercises)", label: "Exercises", color: .blue)
            HistoryStatPill(icon: "clock.fill", value: formatTotalDuration(), label: "Total Time", color: .green)
        }
    }
    
    private func formatTotalDuration() -> String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 3
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Workouts Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Complete your first workout to see it here!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 12, x: 0, y: 6)
    }
}

// MARK: - History Stat Pill
struct HistoryStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - Workout History Day Section
struct WorkoutHistoryDaySection: View {
    let date: Date
    let workouts: [Workout]
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayDate: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(displayDate)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(workouts.count) workout\(workouts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 4)
            
            // Workout cards - using same style as home page
            VStack(spacing: 12) {
                ForEach(workouts, id: \.id) { workout in
                    RecentWorkoutCard(workout: workout)
                }
            }
        }
    }
}

// MARK: - Workout History View (Sheet - Legacy)
struct WorkoutHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == true"),
        animation: .none)  // Disable animation for faster scroll
    private var allWorkouts: FetchedResults<Workout>
    
    // Group workouts by date
    private var groupedWorkouts: [(Date, [Workout])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allWorkouts) { workout in
            calendar.startOfDay(for: workout.date ?? Date())
        }
        return grouped.sorted { $0.key > $1.key } // Most recent first
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient matching home tab and workout complete
                LinearGradient(
                    colors: [
                        Color(red: 0.85, green: 0.92, blue: 1.0),
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea(.all)
                
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Custom header
                            customHeaderView
                            
                            // Main content
                            LazyVStack(spacing: 24) {
                                if groupedWorkouts.isEmpty {
                                    emptyStateView
                                } else {
                                    ForEach(Array(groupedWorkouts.enumerated()), id: \.offset) { index, dayGroup in
                                        WorkoutDaySection(date: dayGroup.0, workouts: dayGroup.1)
                                            .padding(.horizontal, 20)
                                    }
                                }
                            }
                            .padding(.top, 20)
                            .padding(.bottom, 100)
                        }
                        .id("top")
                    }
                }
                
                // Status bar overlay
                VStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 0.92, blue: 1.0).opacity(0.9),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                    .ignoresSafeArea(.all, edges: .top)
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Custom Header View
    private var customHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Page title with Close button
            HStack {
                Text("Workout History")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Spacer()
                
                // Close button
                Button(action: {
                    dismiss()
                }) {
                    Text("Close")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Trophy icon with gradient like workout complete
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.8, blue: 0.8),
                                Color(red: 0.0, green: 0.9, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("No Workouts Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Complete your first workout to see it here!\nYour fitness journey starts with a single step.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 80)
        .padding(.bottom, 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Workout Day Section
struct WorkoutDaySection: View {
    let date: Date
    let workouts: [Workout]
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private var isYesterday: Bool {
        Calendar.current.isDateInYesterday(date)
    }
    
    private var displayDate: String {
        if isToday {
            return "Today"
        } else if isYesterday {
            return "Yesterday"
        } else {
            return dateFormatter.string(from: date)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Date header with home page styling
            HStack {
                Text(displayDate)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.2, green: 0.4, blue: 0.8), location: 0.0),
                                .init(color: Color(red: 0.2, green: 0.4, blue: 0.8), location: 0.7),
                                .init(color: Color(red: 0.2, green: 0.4, blue: 0.8), location: 0.85),
                                .init(color: Color.blue.opacity(0.5), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .white.opacity(0.3), radius: 1, x: 0, y: 1)
                
                Spacer()
                
                Text("\(workouts.count) workout\(workouts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial.opacity(0.5))
                    )
            }
            .padding(.horizontal, 4)
            
            // Workout cards
            VStack(spacing: 16) {
                ForEach(workouts, id: \.id) { workout in
                    ExpandedWorkoutCard(workout: workout)
                }
            }
        }
    }
}

// MARK: - Expanded Workout Card
struct ExpandedWorkoutCard: View {
    let workout: Workout
    @Environment(\.colorScheme) private var colorScheme
    
    // Convert workout exercises to array for easier handling
    private var workoutExercises: [WorkoutExercise] {
        (workout.exercises?.allObjects as? [WorkoutExercise]) ?? []
    }
    
    // Calculate total stats
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            total + (workoutExercise.sets?.count ?? 0)
        }
    }
    
    private var totalReps: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.reduce(0) { $0 + Int($1.reps) }
        }
    }
    
    private var totalWeight: Double {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }
    
    // Get unique muscle groups (using safe accessors)
    private var muscleGroups: [String] {
        let allMuscleGroups = workoutExercises.flatMap { $0.safeMuscleGroups }
        return Array(Set(allMuscleGroups)).sorted()
    }
    
    var body: some View {
        NavigationLink(destination: WorkoutHistoryDetailView(workout: workout)) {
            HStack(spacing: 16) {
                // Workout icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green, Color.blue]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .green.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    // Day and date combined (smaller and different grey)
                    Text("\(getDayName(for: workout.date ?? Date())) · \(formatFullDate(workout.date ?? Date()))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color(.systemGray2))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                    
                    // Workout type (main title)
                    Text(getWorkoutType(for: workout.date ?? Date()))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                    
                    // Workout metrics with icons
                    HStack(spacing: 16) {
                        // Duration
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(formatDuration(workout.duration))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        
                        // Exercises count
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("\(workout.exercises?.count ?? 0)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        
                        // XP earned
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("+\(Int(workout.xpEarned))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Functions
    private func getDayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func getWorkoutType(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        switch hour {
        case 5..<12:
            return "Morning Workout"
        case 12..<17:
            return "Afternoon Workout"
        case 17..<21:
            return "Evening Workout"
        default:
            return "Night Workout"
        }
    }
    
    private func formatDuration(_ duration: Int32) -> String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - History Exercise Row View
struct HistoryExerciseRowView: View {
    let workoutExercise: WorkoutExercise
    
    private var sets: [WorkoutSet] {
        (workoutExercise.sets?.allObjects as? [WorkoutSet]) ?? []
    }
    
    private var completedSets: [WorkoutSet] {
        sets.filter { $0.isCompleted }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Exercise name (uses nickname if user has one set)
            VStack(alignment: .leading, spacing: 1) {
                Text(workoutExercise.safeDisplayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(completedSets.count) sets")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Best set info
            if let bestSet = completedSets.max(by: { $0.weight < $1.weight }) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(bestSet.weight)) lbs")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("\(bestSet.reps) reps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
}

// MARK: - History Stat Item
struct HistoryStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 14)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helper Components for Program Widget

struct DashboardStatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Streak Info Sheet
struct StreakInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    private var currentStreak: Int {
        Int(userManager.currentUser?.currentStreak ?? 0)
    }
    
    private var longestStreak: Int {
        Int(userManager.currentUser?.longestStreak ?? 0)
    }
    
    private var daysPerWeek: Int {
        max(2, Int(userManager.currentUser?.availableDays ?? 4))
    }
    
    private var maxRestDays: Int {
        userManager.getMaxAllowedRestDays()
    }
    
    private var streakStatus: (isAtRisk: Bool, daysRemaining: Int, message: String) {
        userManager.getStreakStatus()
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Big flame with current streak
                    streakHeroSection
                    
                    // Status message
                    statusSection
                    
                    // How it works
                    howItWorksSection
                    
                    // Your schedule
                    yourScheduleSection
                    
                    // Tips
                    tipsSection
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: colorScheme == .dark 
                        ? [Color(white: 0.08), Color(white: 0.05)]
                        : [Color(white: 0.98), Color(white: 0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Your Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Streak Hero
    private var streakHeroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                
                // Solid fill behind the flame to fill the hole
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.red.opacity(0.9)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 68, height: 68)
                    .offset(y: 10)
                
                // Flame
                Image(systemName: "flame.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .orange.opacity(0.5), radius: 20)
                
                // Streak number
                Text("\(currentStreak)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(y: 10)
            }
            
            Text(currentStreak == 1 ? "Workout Streak" : "Workout Streak")
                .font(.title2)
                .fontWeight(.bold)
            
            // Best streak
            if longestStreak > currentStreak {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.yellow)
                    Text("Best: \(longestStreak)")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: streakStatus.isAtRisk ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(streakStatus.isAtRisk ? .orange : .green)
                
                Text(streakStatus.message)
                    .font(.headline)
                    .foregroundColor(streakStatus.isAtRisk ? .orange : .primary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(streakStatus.isAtRisk ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
            )
        }
    }
    
    // MARK: - How It Works Section
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("How Streaks Work", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 12) {
                streakRuleRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "Rest days don't break your streak!",
                    subtitle: "Recovery is part of training"
                )
                
                streakRuleRow(
                    icon: "calendar",
                    color: .blue,
                    title: "Based on YOUR schedule",
                    subtitle: "You work out \(daysPerWeek) days/week"
                )
                
                streakRuleRow(
                    icon: "clock.fill",
                    color: .purple,
                    title: "Up to \(maxRestDays) rest days allowed",
                    subtitle: "Between workouts without losing streak"
                )
                
                streakRuleRow(
                    icon: "xmark.circle.fill",
                    color: .red,
                    title: "Streak resets after \(maxRestDays + 1)+ days",
                    subtitle: "Without completing a workout"
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Your Schedule Section
    private var yourScheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Your Training Schedule", systemImage: "figure.strengthtraining.traditional")
                .font(.headline)
                .foregroundColor(.blue)
            
            HStack(spacing: 16) {
                scheduleStatCard(
                    value: "\(daysPerWeek)",
                    label: "Days/Week",
                    icon: "calendar.badge.clock",
                    color: .blue
                )
                
                scheduleStatCard(
                    value: "\(maxRestDays)",
                    label: "Max Rest Days",
                    icon: "bed.double.fill",
                    color: .purple
                )
                
                scheduleStatCard(
                    value: "\(currentStreak)",
                    label: "Current",
                    icon: "flame.fill",
                    color: .orange
                )
            }
        }
    }
    
    // MARK: - Tips Section
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Pro Tips", systemImage: "star.fill")
                .font(.headline)
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 12) {
                tipRow("🏋️", "Any completed workout counts toward your streak")
                tipRow("😴", "Rest days are essential for muscle recovery")
                tipRow("📅", "Consistency > Intensity for building habits")
                tipRow("🔔", "Enable notifications to never miss a workout")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Helper Views
    private func streakRuleRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func scheduleStatCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private func tipRow(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
                .font(.title3)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

struct WorkoutDetailBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
}
