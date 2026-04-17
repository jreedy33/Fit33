import SwiftUI
import CoreData

extension DashboardView {
    // MARK: - Custom Header View
    var customHeaderView: some View {
        HStack(alignment: .center) {
            Image("fit33-logo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 140, height: 55)
                .clipped()
                .accessibilityHidden(true)
            
            Spacer()
            
            // Timer, widget settings, and profile icon grouped together
            HStack(spacing: 8) {
                // Active workout timer (only shows when workout is active)
                if workoutManager.isWorkoutActive {
                    Text(workoutManager.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(.ultraThinMaterial)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                
                // Widget settings button (three dots)
                Button(action: {
                    HapticManager.tap()
                    showingWidgetSettings = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .accessibilityLabel("Widget settings")
                .accessibilityHint("Customize dashboard widgets")
                .buttonStyle(PlainButtonStyle())
                
                // Add spacing between ... and profile icon
                Spacer()
                    .frame(width: 4)
                
                // Profile button with hollow blue gradient ring and photo/person icon
                NavigationLink(value: DashboardRoute.profile) {
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
                                            .font(.ds_labelLarge)
                                            .foregroundColor(.white)
                                    @unknown default:
                                        Image(systemName: "person.fill")
                                            .font(.ds_labelLarge)
                                            .foregroundColor(.white)
                                    }
                                }
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.ds_labelLarge)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Red indicator dot - isolated component to prevent DashboardView re-renders
                        FriendNotificationBadge()
                            .offset(x: 3, y: -3)
                    }
                }
                .accessibilityLabel("Profile")
                .accessibilityHint("View your profile and settings")
                .offset(y: 2)
            }
            .animation(.easeInOut(duration: 0.2), value: workoutManager.isWorkoutActive)
        }
        .padding(.horizontal, Spacing.xxs)
    }
    
    // MARK: - Notification Permission Banner
    // Persist dismissed state so it doesn't flicker on view recreation
    
    var notificationPermissionBanner: some View {
        // All conditions are checked in the parent - this just renders the content
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
                        .font(.ds_heading3).fontWeight(.semibold)
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
                        .padding(Spacing.xs)
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
                        .font(.ds_labelMedium)
                    Text("Enable Notifications")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.md)
            }
        }
        .padding(Spacing.md)
        .onboardingCardStyle(accentColor: .orange, secondaryColor: .red, isSelected: true, cornerRadius: CornerRadius.lg)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // Get the user's first name only (remove last name)
    func getFirstName() -> String {
        let fullName = userManager.currentUser?.name ?? "there"
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        return firstName.isEmpty ? "there" : firstName
    }
    
    // Check if this is the user's first time seeing the dashboard after account creation
    func checkIsFirstVisit() -> Bool {
        guard let userId = userManager.currentUser?.id else { return true }
        return !UserDefaults.standard.bool(forKey: "has_been_welcomed_\(userId.uuidString)")
    }
    
    // Welcome message based on first visit
    func getWelcomeMessage() -> String {
        checkIsFirstVisit() ? "Welcome to Fit33," : "Welcome back,"
    }
    
    var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top section with Welcome back and Level
            HStack {
                Text(getWelcomeMessage())
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // User Level Display - floating badge (no background)
                HStack(spacing: 4) {
                    Image(systemName: userManager.getLevelIcon())
                        .font(.ds_caption)
                        .foregroundColor(userManager.getLevelColor())
                    
                    Text(userManager.getLevelTitle())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(userManager.getLevelColor())
                }
                .accessibilityLabel("Level \(userManager.getLevel()): \(userManager.getLevelTitle())")
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
                .accessibilityLabel("Current streak: \(userManager.currentUser?.currentStreak ?? 0) days")
                .accessibilityHint("Tap for streak details")
                .buttonStyle(.plain)
                
                // User info section - moved to the right
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(getFirstName())
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if userManager.isVerified || userManager.isGoldVerified {
                            VerifiedBadge(size: 16, isGold: userManager.isGoldVerified)
                        }
                    }
                    
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
        .padding(.horizontal, Spacing.md)
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
    
    var startWorkoutButton: some View {
        VStack(spacing: 12) {
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
                .frame(maxWidth: .infinity)
                .frame(height: 140)
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
                                Color.cardBackground
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
                .accessibilityLabel("Start custom workout")
                .accessibilityHint("Build your own workout from scratch")
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
                .frame(maxWidth: .infinity)
                .frame(height: 140)
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
                                Color.cardBackground
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
                .accessibilityLabel("Start auto workout")
                .accessibilityHint("Generate a workout based on your history")
                .buttonStyle(PlainButtonStyle())
            
            }
        }
    }
    
    // MARK: - Dashboard Widgets Row
    var dashboardWidgetsRow: some View {
        let showBoth = showWeightTrackerWidget && showHydrationWidget
        
        return Group {
            if showBoth {
                // Two widgets side by side
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    if showWeightTrackerWidget {
                        DashboardWeightWidget(isCompact: true)
                    }
                    if showHydrationWidget {
                        DashboardHydrationWidget(isCompact: true)
                    }
                }
            } else {
                // Single widget expanded
                if showWeightTrackerWidget {
                    DashboardWeightWidget(isCompact: false)
                }
                if showHydrationWidget {
                    DashboardHydrationWidget(isCompact: false)
                }
            }
        }
    }
    
    var destinationForTodaysWorkout: some View {
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

    func handleWorkoutSelection(type: PendingWorkoutType) {
        // 🔧 Debounce: Prevent double-taps
        guard !isNavigating else { return }
        isNavigating = true
        
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }
        
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
}
