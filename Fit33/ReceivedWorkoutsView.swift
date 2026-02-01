import SwiftUI
import CoreData

// MARK: - Received Workouts View
/// View and manage workouts received from friends

struct ReceivedWorkoutsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    
    // Use StateObject wrapper to prevent unnecessary re-renders during navigation
    // The view will still observe changes, but won't be recreated
    @ObservedObject private var friendService = FriendService.shared
    
    // Only read DeepLinkManager and AdManager values when needed, don't observe
    private var deepLinkManager: DeepLinkManager { DeepLinkManager.shared }
    private var adsEnabled: Bool { AdManager.shared.adsEnabled }
    
    @State private var selectedWorkout: ReceivedWorkoutDTO?
    @State private var navigateToDetail = false
    @State private var hasLoadedInitialData = false // Prevent navigation reset from data reloading
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        ZStack {
            AdaptiveGradient.stats(for: colorScheme)
                .ignoresSafeArea()
            
            if friendService.receivedWorkouts.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(0..<totalItemsWithAds, id: \.self) { index in
                        if isAdPosition(index) && adsEnabled {
                            // Native ad card
                            NativeAdCardView()
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        } else {
                            // Workout card
                            let workoutIndex = getWorkoutIndex(for: index)
                            if workoutIndex < friendService.receivedWorkouts.count {
                                let workout = friendService.receivedWorkouts[workoutIndex]
                                ReceivedWorkoutCard(workout: workout) {
                                    selectedWorkout = workout
                                    navigateToDetail = true
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteWorkout(workout)
                                    } label: {
                                        Label("Delete", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            
            // Navigation link for full-page detail view
            NavigationLink(
                destination: Group {
                    if let workout = selectedWorkout {
                        ReceivedWorkoutDetailView(workout: workout)
                    }
                },
                isActive: $navigateToDetail
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationTitle("Received Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            // Only load data on first appear to prevent navigation disruption
            guard !hasLoadedInitialData else { return }
            hasLoadedInitialData = true
            
            Task {
                await friendService.loadReceivedWorkouts()
                
                // Check if we have a pending workout to open from notification deep link
                if let pendingId = deepLinkManager.pendingReceivedWorkoutId {
                    // Find the workout with this ID
                    if let workout = friendService.receivedWorkouts.first(where: { $0.id.uuidString == pendingId }) {
                        selectedWorkout = workout
                        navigateToDetail = true
                    }
                    // Clear the pending ID
                    deepLinkManager.pendingReceivedWorkoutId = nil
                }
            }
        }
    }
    
    // MARK: - Ad Helpers
    
    /// Calculate total items including ads (every 3rd position is an ad)
    private var totalItemsWithAds: Int {
        guard adsEnabled else {
            return friendService.receivedWorkouts.count
        }
        
        let workoutCount = friendService.receivedWorkouts.count
        let adCount = workoutCount / 2 // Insert ad after every 2 workouts
        return workoutCount + adCount
    }
    
    /// Check if this position should show an ad (positions 2, 5, 8, 11, etc.)
    private func isAdPosition(_ index: Int) -> Bool {
        guard adsEnabled else { return false }
        // Ad at positions 2, 5, 8, 11... (every 3rd position)
        return (index + 1) % 3 == 0
    }
    
    /// Get the actual workout index for a display index (accounting for ads)
    private func getWorkoutIndex(for displayIndex: Int) -> Int {
        guard adsEnabled else { return displayIndex }
        
        // Calculate how many ads appear before this position
        let adsBeforeThisIndex = displayIndex / 3
        return displayIndex - adsBeforeThisIndex
    }
    
    // MARK: - Actions
    
    private func deleteWorkout(_ workout: ReceivedWorkoutDTO) {
        HapticManager.impact(.medium)
        Task {
            _ = await friendService.deleteReceivedWorkout(workoutId: workout.id)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text("No Workouts Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Workouts sent to you by friends\nwill appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Received Workout Card
/// Matches RecentWorkoutCard style but shows sender's photo instead of checkmark

struct ReceivedWorkoutCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var premiumManager = PremiumManager.shared
    
    let workout: ReceivedWorkoutDTO
    let onTap: () -> Void
    
    @State private var showingPremiumUpgrade = false
    
    private var isUnread: Bool {
        workout.viewedAt == nil && workout.status == "pending"
    }
    
    /// Check if this saved workout requires premium to open
    private var requiresPremium: Bool {
        workout.status == "saved" && !premiumManager.isPremiumUser
    }
    
    // Workout accent gradient (blue/purple for received workouts)
    private var workoutGradient: [Color] {
        [Color.blue, Color.purple.opacity(0.8)]
    }
    
    // Total sets from exercises
    private var totalSets: Int {
        workout.exerciseSets.reduce(0, +)
    }
    
    // Estimated duration (3 min per set rough estimate)
    private var estimatedMinutes: Int {
        workout.estimatedDuration ?? max(15, totalSets * 3)
    }
    
    var body: some View {
        Button(action: {
            if requiresPremium {
                HapticManager.impact(.light)
                showingPremiumUpgrade = true
            } else {
                onTap()
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Top section - Sender photo, Workout Name, Date
                HStack(alignment: .top, spacing: 12) {
                    // Sender photo in gradient ring (replaces checkmark)
                    senderAvatarView
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Workout name
                        Text(workout.workoutName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        // From + Date
                        HStack(spacing: 4) {
                            Text("From \(workout.senderName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(formatSmartDate(workout.createdAt))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Status badge (NEW or Saved)
                    statusBadge
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                Divider()
                    .padding(.vertical, 12)
                
                // Bottom section - Stats (matching RecentWorkoutCard)
                HStack(spacing: 0) {
                    // Duration
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                                .foregroundColor(workoutGradient[0])
                            Text("\(estimatedMinutes)m")
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
                            Text("\(workout.exerciseCount)")
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
                    
                    // Message indicator (if has message)
                    if let message = workout.message, !message.isEmpty {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1, height: 35)
                        
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.bubble.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }
                            Text("Message")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
            )
            .overlay(
                // Unread indicator border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isUnread ? workoutGradient[0].opacity(0.6) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .savedWorkouts)
        }
    }
    
    // MARK: - Sender Avatar View
    private var senderAvatarView: some View {
        CachedFriendPhoto(
            friendId: workout.senderId.uuidString,
            photoUrl: workout.senderProfilePhotoUrl,
            name: workout.senderName,
            size: 44,
            showGradientRing: true,
            gradientColors: workoutGradient
        )
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch workout.status {
        case "pending":
            Text("NEW")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.blue))
        case "saved":
            // Show PRO badge for free users, Saved badge for premium users
            if requiresPremium {
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9))
                    Text("PRO")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.black.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.75, blue: 0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10))
                    Text("Saved")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().stroke(Color.green, lineWidth: 1))
            }
        default:
            EmptyView()
        }
    }
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Received Workout Detail View (Full Page - Matches AutoWorkoutPreviewView Style)

struct ReceivedWorkoutDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    
    @ObservedObject private var premiumManager = PremiumManager.shared
    
    let workout: ReceivedWorkoutDTO
    
    @State private var isStartingWorkout = false
    @State private var showingExerciseDetail = false
    @State private var selectedCoreDataExercise: Exercise? = nil
    @State private var showingSavedConfirmation = false
    @State private var showingPremiumUpgrade = false
    
    // Theme colors (blue/purple gradient for received workouts)
    private let themeColor: Color = .blue
    private let secondaryThemeColor: Color = .purple
    
    /// Check if user needs premium to start this received workout
    private var requiresPremiumToStart: Bool {
        !premiumManager.isPremiumUser
    }
    
    private var totalSets: Int {
        workout.exerciseSets.reduce(0, +)
    }
    
    private var estimatedMinutes: Int {
        workout.estimatedDuration ?? max(15, totalSets * 3)
    }
    
    var body: some View {
        ZStack {
            // Background gradient matching AutoWorkoutPreviewView style
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [themeColor.opacity(0.2), secondaryThemeColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [themeColor.opacity(0.3), secondaryThemeColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Header card (workout info + sender)
                    workoutHeader
                    
                    // Message section (if any)
                    if let message = workout.message, !message.isEmpty {
                        messageCard(message)
                    }
                    
                    // Exercise list section
                    exerciseListSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Your Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    GoButtonState.shared.hide(reason: "ReceivedWorkout_back")
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: saveWorkout) {
                    Image(systemName: workout.status == "saved" ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(workout.status == "saved" ? .green : themeColor)
                }
            }
        }
        .onAppear {
            markAsViewed()
            
            // Show GO! button
            GoButtonState.shared.show(
                primaryColor: themeColor,
                secondaryColor: secondaryThemeColor,
                source: "ReceivedWorkoutPreview"
            ) {
                let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
                heavyImpact.impactOccurred()
                
                // Check if this is a saved workout and user is not premium
                if requiresPremiumToStart {
                    showingPremiumUpgrade = true
                } else {
                    startWorkout()
                }
            }
            
            // Prefetch exercise history
            Task {
                _ = await ExerciseHistoryService.shared.fetchPreviousSetsForExercises(workout.exerciseNames)
            }
        }
        .onDisappear {
            GoButtonState.shared.hide(reason: "ReceivedWorkout_disappeared")
        }
        .sheet(isPresented: $showingExerciseDetail) {
            if let exercise = selectedCoreDataExercise {
            NavigationView {
                    ExerciseDetailView(exercise: exercise)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingExerciseDetail = false
                                }
                            }
                        }
                }
            }
        }
        .alert("Workout Saved! ✓", isPresented: $showingSavedConfirmation) {
            Button("OK") {}
        } message: {
            Text("This workout has been saved. You can find it in your received workouts anytime.")
        }
        .sheet(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .savedWorkouts)
        }
    }
    
    // MARK: - Workout Header (Matches AutoWorkoutPreviewView style)
    
    private var workoutHeader: some View {
        VStack(spacing: 0) {
            // Top section: Workout badge + title + sender info
        HStack(spacing: 14) {
                // Workout badge with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                                colors: [themeColor, secondaryThemeColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                        .frame(width: 46, height: 46)
                
                    Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.workoutName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Label("\(workout.exerciseCount) exerci...", systemImage: "figure.strengthtraining.traditional")
                        Label("\(estimatedMinutes) min", systemImage: "clock.fill")
                        Label("60s rest", systemImage: "timer")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            Spacer()
        }
            .padding(14)
            
            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 14)
            
            // Sender info section
            HStack(spacing: 12) {
                // Sender avatar with cached photo
                CachedFriendPhoto(
                    friendId: workout.senderId.uuidString,
                    photoUrl: workout.senderProfilePhotoUrl,
                    name: workout.senderName,
                    size: 34,
                    showGradientRing: true,
                    gradientColors: [themeColor, secondaryThemeColor]
                )
                        
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sent by \(workout.senderName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                            
                    Text(formatSmartDate(workout.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                        
                Spacer()
                
                // Status badge
                statusBadge
            }
            .padding(14)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 3)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch workout.status {
        case "pending":
            Text("NEW")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(themeColor))
        case "saved":
            HStack(spacing: 4) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 10))
                Text("Saved")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().stroke(Color.green, lineWidth: 1))
        default:
            EmptyView()
        }
    }
    
    // MARK: - Message Card
    
    private func messageCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 14))
                    .foregroundColor(themeColor)
                Text("Message from \(workout.senderName)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            Text("\"\(message)\"")
                .font(.body)
                .italic()
                .foregroundColor(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 3)
    }
    
    // MARK: - Exercise List Section (Matches AutoWorkoutPreviewView style)
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Exercises")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("tap for info")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                ForEach(Array(workout.exerciseNames.enumerated()), id: \.offset) { index, name in
                    ReceivedExerciseCard(
                        exerciseName: name,
                sets: workout.exerciseSets.indices.contains(index) ? workout.exerciseSets[index] : 3,
                reps: workout.exerciseReps.indices.contains(index) ? workout.exerciseReps[index] : "10",
                        themeColor: themeColor,
                        onTapCard: {
                            // Find matching Exercise from Core Data for full detail view
                            if let coreDataExercise = ExerciseLibraryService.shared.getExercise(byName: name) {
                                selectedCoreDataExercise = coreDataExercise
                                showingExerciseDetail = true
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func markAsViewed() {
        Task {
            await FriendService.shared.markWorkoutViewed(workoutId: workout.id)
        }
    }
    
    private func startWorkout() {
        guard !workoutManager.isWorkoutActive else { return }
        
        isStartingWorkout = true
        HapticManager.impact(.heavy)
        
        // Lookup Core Data exercises
        let coreDataExercises = ExerciseLibraryService.shared.getExercises(byNames: workout.exerciseNames)
        
        guard !coreDataExercises.isEmpty else {
                print("❌ No exercises found in Core Data")
                isStartingWorkout = false
                return
            }
            
        // Create Workout entity
        let context = PersistenceController.shared.container.viewContext
        let newWorkout = Workout(context: context)
            newWorkout.id = UUID()
            newWorkout.name = workout.workoutName
            newWorkout.date = Date()
        newWorkout.duration = 0
            newWorkout.isCompleted = false
        
        // Start workout via WorkoutManager
        workoutManager.startWorkout(
            workout: newWorkout,
            exercises: coreDataExercises,
            insights: nil,
            programDay: nil,
            programDayFocus: workout.workoutName
        )
            
            // Mark as completed in friend service
            Task {
                await FriendService.shared.markWorkoutCompleted(workoutId: workout.id)
            }
            
        // Hide GO button and dismiss
        GoButtonState.shared.hide(reason: "ReceivedWorkout_started")
    }
    
    private func saveWorkout() {
        // Check if user is premium - free users must upgrade to save workouts
        guard premiumManager.isPremiumUser else {
            HapticManager.impact(.light)
            showingPremiumUpgrade = true
            return
        }
        
        HapticManager.impact(.medium)
        Task {
            do {
                try await FriendService.shared.saveSharedWorkout(workoutId: workout.id)
                showingSavedConfirmation = true
                HapticManager.notification(.success)
            } catch {
                print("❌ Error saving workout: \(error)")
            }
        }
    }
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
        let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today at \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
        }
    }
}

// MARK: - Received Exercise Card (Matches AutoExerciseCard style)

struct ReceivedExerciseCard: View {
    let exerciseName: String
    let sets: Int
    let reps: String
    let themeColor: Color
    let onTapCard: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Get category color based on exercise
    private var categoryColor: Color {
        // Try to get category from Core Data
        if let exercise = ExerciseLibraryService.shared.getExercise(byName: exerciseName),
           let category = exercise.category?.lowercased() {
            switch category {
            case "chest": return .red
            case "back": return .blue
            case "legs": return .green
            case "shoulders": return .orange
            case "arms": return .purple
            case "core": return .yellow
            default: return themeColor
            }
        }
        return themeColor
    }
    
    private var categoryIcon: String {
        if let exercise = ExerciseLibraryService.shared.getExercise(byName: exerciseName),
           let category = exercise.category?.lowercased() {
            switch category {
            case "chest": return "figure.strengthtraining.traditional"
            case "back": return "figure.rowing"
            case "legs": return "figure.run"
            case "shoulders": return "figure.arms.open"
            case "arms": return "dumbbell.fill"
            case "core": return "figure.core.training"
            default: return "dumbbell.fill"
            }
        }
        return "dumbbell.fill"
    }
    
    private var categoryName: String {
        if let exercise = ExerciseLibraryService.shared.getExercise(byName: exerciseName),
           let category = exercise.category {
            return category
        }
        return "Exercise"
    }
    
    private var equipmentName: String {
        if let exercise = ExerciseLibraryService.shared.getExercise(byName: exerciseName),
           let equipment = exercise.equipment {
            return equipment
        }
        return "Bodyweight"
    }
    
    var body: some View {
        Button(action: onTapCard) {
            HStack(spacing: 12) {
                // Category icon (matching exercise library style)
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: categoryIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(categoryColor)
                }
                
                // Exercise details
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(categoryName)
                            .font(.caption)
                            .foregroundColor(categoryColor)
                            .fontWeight(.medium)
                        
                        Text("•")
                .font(.caption2)
                .foregroundColor(.secondary)
                        
                        Text(equipmentName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Info icon
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
        )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Edit Received Workout View (Future Use)

struct EditReceivedWorkoutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    let workout: ReceivedWorkoutDTO
    @Binding var exercises: [SelectedExerciseForFriend]
    let onStartWorkout: () -> Void
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        ZStack {
            AdaptiveGradient.stats(for: colorScheme)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    Text("Customize this workout before starting")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    ForEach($exercises) { $exercise in
                        EditableExerciseCard(exercise: $exercise)
                    }
                    
                    // Start button
                    Button(action: {
                        HapticManager.impact(.heavy)
                        dismiss()
                        onStartWorkout()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            Text("Start Edited Workout")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.green, Color.mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Edit Workout")
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

// MARK: - Editable Exercise Card

struct EditableExerciseCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var exercise: SelectedExerciseForFriend
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(exercise.name)
                .font(.headline)
            
            HStack(spacing: 16) {
                // Sets
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            if exercise.sets > 1 { exercise.sets -= 1 }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        Text("\(exercise.sets)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .frame(minWidth: 30)
                        
                        Button(action: {
                            exercise.sets += 1
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
                
                // Reps
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., 10-12", text: $exercise.reps)
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(width: 80)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(.systemGray6))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

#Preview {
    NavigationView {
        ReceivedWorkoutsView()
            .environmentObject(WorkoutManager.shared)
            .environmentObject(UserManager())
    }
}
